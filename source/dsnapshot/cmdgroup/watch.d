/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

The design follows a basic actor system for handling the threads.
*/
module dsnapshot.cmdgroup.watch;

import core.thread : Thread;
import core.time : dur;
import logger = std.experimental.logger;
import std.algorithm : filter, map;
import std.array : empty;
import std.concurrency : spawn, spawnLinked, Tid, thisTid, send, receive,
    receiveTimeout, receiveOnly, OwnerTerminated;
import std.exception : collectException;

import sumtype;

import dsnapshot.config : Config;
import dsnapshot.types;

import dsnapshot.backend;
import dsnapshot.console;
import dsnapshot.exception;
import dsnapshot.from;
import dsnapshot.layout;
import dsnapshot.layout_utils;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

int cli(const Config.Global cglobal, const Config.Watch cwatch, SnapshotConfig[] snapshots) {
    void act(const SnapshotConfig s) @trusted {
        auto createSnapshotTid = spawnLinked(&actorCreateSnapshot, cast(immutable) s);
        auto filterAndTriggerSyncTid = spawnLinked(&actorFilterAndTriggerSync,
                cast(immutable) s, createSnapshotTid);
        auto watchTid = spawnLinked(&actorWatch, cast(immutable) s, filterAndTriggerSyncTid);

        send(createSnapshotTid, filterAndTriggerSyncTid);
        send(createSnapshotTid, thisTid);
        send(createSnapshotTid, RegisterListenerDone.value);

        send(filterAndTriggerSyncTid, watchTid);

        send(watchTid, Start.value);

        ulong countSnapshots;
        while (countSnapshots < cwatch.maxSnapshots) {
            // TODO: should this be triggered? maybe on ctrl+c?
            receiveOnly!CreateSnapshotDone;
            countSnapshots++;
        }
    }

    foreach (const s; snapshots.filter!(a => cwatch.name.value == a.name)) {
        logger.info("# Watching ", s.name);
        scope (exit)
            logger.info("# Done watching ", s.name);

        try {
            act(s);
        } catch (SnapshotException e) {
            e.errMsg.match!(a => a.print);
            logger.error(e.msg);
        } catch (Exception e) {
            logger.error(e.msg);
        }

        return 0;
    }

    logger.info("No snapshot configuration named ", cwatch.name.value);
    return 1;
}

private:

enum FilesystemChange {
    value,
}

enum CreateSnapshot {
    value,
}

enum CreateSnapshotDone {
    value,
}

enum Shutdown {
    value,
}

enum Start {
    value,
}

enum RegisterListenerDone {
    value,
}

/** Watch a path for changes on the filesystem.
 */
void actorWatch(immutable SnapshotConfig snapshot, Tid onFsChange) nothrow {
    import std.datetime : Duration;
    import fswatch : FileWatch, FileChangeEvent, FileChangeEventType;

    void eventHandler(FileChangeEvent[] events) @safe {
        if (!events.empty) {
            () @trusted {
                send(onFsChange, FilesystemChange.value);
                receiveOnly!CreateSnapshotDone;
            }();
        }

        foreach (event; events) {
            final switch (event.type) with (FileChangeEventType) {
            case createSelf:
                logger.trace("Observable path created");
                break;
            case removeSelf:
                logger.trace("Observable path deleted");
                break;
            case create:
                logger.tracef("'%s' created", event.path);
                break;
            case remove:
                logger.tracef("'%s' removed", event.path);
                break;
            case rename:
                logger.tracef("'%s' renamed to '%s'", event.path, event.newPath);
                break;
            case modify:
                logger.tracef("'%s' contents modified", event.path);
                break;
            }
        }
    }

    string extractPath() @trusted nothrow {
        try {
            auto syncBe = makeSyncBackend(cast() snapshot);
            return syncBe.flow.match!((None a) => null,
                    (FlowLocal a) => a.src.value.Path.toString, (FlowRsyncToLocal a) => null,
                    (FlowLocalToRsync a) => a.src.value.Path.toString);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        return null;
    }

    void actFallback(const Duration poll) @trusted {
        send(onFsChange, FilesystemChange.value);
        receiveOnly!CreateSnapshotDone;
        Thread.sleep(poll);
    }

    void actNormal(string path, const Duration poll) @trusted {
        auto watcher = FileWatch(path, true);
        while (true) {
            eventHandler(watcher.getEvents());
            Thread.sleep(poll);
        }
    }

    auto path = extractPath;
    const poll = () {
        if (path.empty) {
            logger.info("No local path to watch for changes. Falling back to polling.")
                .collectException;
            return 10.dur!"seconds";
        } else {
            logger.infof("Watching %s for changes", path).collectException;
            // arbitrarily chosen a timeout that is hopefully fast enough but not too fast.
            return 200.dur!"msecs";
        }
    }();

    () @trusted { receiveOnly!Start.collectException; }();

    if (path.empty) {
        while (true) {
            try {
                actFallback(poll);
            } catch (OwnerTerminated) {
                break;
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }

    } else {
        while (true) {
            try {
                actNormal(path, poll);
            } catch (OwnerTerminated) {
                break;
            } catch (Exception e) {
                logger.warning(e.msg).collectException;
            }
        }
    }
}

/** Collect filesystem events to trigger a new snapshot when the first bucket
 * is empty in the layout.
 */
void actorFilterAndTriggerSync(immutable SnapshotConfig snapshot_, Tid onSync) nothrow {
    import std.datetime : Clock, SysTime, Duration;

    static struct Process {
    @safe:

        SyncBackend syncBe;
        SnapshotConfig sconf;
        Layout layout;

        SysTime triggerAt;

        this(SyncBackend syncBe, SnapshotConfig sconf) {
            this.syncBe = syncBe;
            this.sconf = sconf;
            this.updateTrigger();
        }

        void updateTrigger() {
            layout = syncBe.update(sconf.layout);

            if (layout.isFirstBucketEmpty) {
                triggerAt = Clock.currTime;
            } else {
                triggerAt = Clock.currTime + (layout.snapshotTimeInBucket(0)
                        .get - layout.times[0].begin);
            }
        }

        Duration timeout() {
            if (layout.isFirstBucketEmpty) {
                return Duration.zero;
            }
            return triggerAt - Clock.currTime;
        }

        bool trigger() {
            return Clock.currTime > triggerAt;
        }
    }

    void act(ref Process process, Tid onSnapshotDone) @trusted {
        bool tooEarly;
        receive((FilesystemChange a) { tooEarly = !process.trigger(); });

        if (tooEarly) {
            logger.trace("Too early, sleeping for ", process.timeout);
            Thread.sleep(process.timeout);
        }

        send(onSync, CreateSnapshot.value);
        receiveOnly!CreateSnapshotDone;
        process.updateTrigger();

        send(onSnapshotDone, CreateSnapshotDone.value);

        logger.info("Next snapshot at the earliest in ", process.timeout);
    }

    try {
        Tid onSnapshotDone = () @trusted { return receiveOnly!Tid; }();

        auto snapshot = () @trusted { return cast() snapshot_; }();

        auto backend = makeSyncBackend(snapshot);

        auto crypt = makeCrypBackend(snapshot.crypt);
        open(crypt, backend.flow);
        scope (exit)
            crypt.close;

        auto process = Process(backend, snapshot);

        while (true) {
            act(process, onSnapshotDone);
        }
    } catch (OwnerTerminated) {
    } catch (Exception e) {
        logger.error(e.msg).collectException;
    }
}

void actorCreateSnapshot(immutable SnapshotConfig snapshot) nothrow {
    import std.datetime : Clock;

    static void act(SnapshotConfig snapshot) @safe {
        auto backend = makeSyncBackend(snapshot);

        auto crypt = makeCrypBackend(snapshot.crypt);
        open(crypt, backend.flow);
        scope (exit)
            crypt.close;

        auto layout = backend.update(snapshot.layout);

        const newSnapshot = () {
            return Clock.currTime.toUTC.toISOExtString ~ snapshotInProgressSuffix;
        }();

        backend.sync(layout, snapshot, newSnapshot);

        backend.publishSnapshot(newSnapshot);
        backend.removeDiscarded(layout);
    }

    Tid[] onSnapshotDone;
    try {
        bool running = true;
        while (running) {
            () @trusted {
                receive((Tid a) => onSnapshotDone ~= a, (RegisterListenerDone a) {
                    running = false;
                });
            }();
        }
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return;
    }

    while (true) {
        try {
            () @trusted {
                scope (exit)
                    () {
                    foreach (t; onSnapshotDone)
                        send(t, CreateSnapshotDone.value);
                }();
                receive((CreateSnapshot a) { act(cast() snapshot); });
            }();
        } catch (OwnerTerminated) {
            break;
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
}
