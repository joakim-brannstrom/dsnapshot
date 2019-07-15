/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backup;

import logger = std.experimental.logger;
import std.exception : collectException;

import dsnapshot.config : Config;
import dsnapshot.types : Snapshot, Path, RsyncConfig, Hooks, LocalAddr;

import sumtype;

version (unittest) {
    import unit_threaded.assertions;
}

int cmdBackup(Config.Global global, Config.Backup backup, Snapshot[] snapshots) {
    int exitStatus;

    foreach (s; snapshots) {
        int snapshotStatus = 1;
        try {
            snapshot(s);
            snapshotStatus = 0;
        } catch (SnapshotException e) {
            e.errMsg.match!(a => a.print);
            logger.error(e.msg);
        } catch (Exception e) {
            logger.error(e.msg);
        }

        exitStatus = (snapshotStatus + exitStatus) == 0 ? 0 : 1;
    }

    return exitStatus;
}

class SnapshotException : Exception {
    this(SnapshotError s) {
        super(null);
        this.errMsg = s;
    }

    SnapshotError errMsg;

    static struct DstIsNotADir {
        void print() {
            logger.error("Destination must be a directory");
        }
    }

    static struct UnableToAcquireWorkLock {
        string dst;
        void print() {
            logger.errorf("'%s' is locked by another dsnapshot instance", dst);
        }
    }

    static struct SyncFailed {
        string src;
        string dst;
        void print() {
            logger.errorf("Failed to sync from '%s' to '%s'", src, dst);
        }
    }

    static struct PreExecFailed {
        void print() {
            logger.error("One or more of the `pre_exec` hooks failed");
        }
    }

    static struct PostExecFailed {
        void print() {
            logger.error("One or more of the `post_exec` hooks failed");
        }
    }
}

alias SnapshotError = SumType!(SnapshotException.DstIsNotADir, SnapshotException.UnableToAcquireWorkLock,
        SnapshotException.SyncFailed, SnapshotException.PreExecFailed,
        SnapshotException.PostExecFailed,);

private:

void snapshot(Snapshot snapshot) {
    import std.file : exists, mkdirRecurse, rename;
    import std.path : buildPath, setExtension;
    import std.datetime : UTC, SysTime, Clock;
    import dsnapshot.types;

    const newSnapshot = () {
        auto c = Clock.currTime;
        c.timezone = UTC();
        return c.toISOExtString;
    }();

    // Extract an updated layout of the snapshots at the destination.
    auto layout = snapshot.syncCmd.match!((None a) => snapshot.layout,
            (RsyncConfig a) => fillLayout(snapshot.layout, a.flow));

    auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

    logger.trace("Updated layout with information from destination: ", layout);

    snapshot.syncCmd.match!((None a) {
        logger.info("No sync done for ", snapshot.name, " (missing command configuration)");
    }, (RsyncConfig a) => sync(a, layout, flow, snapshot.hooks, newSnapshot));

    flow.match!((None a) {}, (FlowLocal a) {
        removeLocalSnapshots(a.dst, layout);
    }, (FlowRsyncToLocal a) { removeLocalSnapshots(a.dst, layout); });
}

void sync(const RsyncConfig conf, const Layout layout, const Flow flow,
        const Hooks hooks, const string newSnapshot) {
    import std.array : empty;
    import std.conv : to;
    import std.file : remove, exists, mkdirRecurse;
    import std.path : buildPath, setExtension;
    import std.process : spawnProcess, wait, execute, spawnShell, executeShell;
    import std.stdio : stdin, File;
    import dsnapshot.types;

    static void setupLocalDest(Path p) {
        if (!exists(p.toString))
            mkdirRecurse(p.toString);
    }

    static int executeHooks(string msg, const string[] hooks, string[string] env) {
        foreach (s; hooks) {
            logger.info(msg, ": ", s);
            if (spawnShell(s, env).wait != 0)
                return 1;
        }
        return 0;
    }

    string src, dst;

    string[] buildOpts() {
        string[] opts = [conf.cmdRsync];
        opts ~= conf.args.dup;

        const latest = layout.firstFullBucket;

        if (conf.oneFs && !latest.isNull)
            opts ~= ["-x"];

        if (conf.useLinkDest && !latest.isNull) {
            flow.match!((None a) {}, (FlowLocal a) {
                opts ~= [
                    "--link-dest", (a.dst.value.Path ~ latest.get.name.value).toString
                ];
            }, (FlowRsyncToLocal a) {
                opts ~= [
                    "--link-dest", (a.dst.value.Path ~ latest.get.name.value).toString
                ];
            });
        }

        foreach (a; conf.exclude)
            opts ~= ["--exclude", a];

        flow.match!((None a) {}, (FlowLocal a) {
            src = a.src.value;
            dst = (a.dst.value.Path ~ newSnapshot).toString;
            opts ~= [src, dst];
        }, (FlowRsyncToLocal a) {
            src = a.src.value;
            dst = (a.dst.value.Path ~ newSnapshot).toString;
            opts ~= [src, dst];
        });
        return opts;
    }

    auto opts = buildOpts();

    // TODO: add handling of remote destinations.
    // Configure local destination
    flow.match!((None a) {}, (FlowLocal a) => setupLocalDest(a.dst.value.Path ~ newSnapshot),
            (FlowRsyncToLocal a) => setupLocalDest(a.dst.value.Path ~ newSnapshot));

    if (src.empty || dst.empty) {
        logger.info("source or destination is empty. Nothing to do.");
        return;
    }

    logger.trace(opts);
    logger.infof("Synchronizing '%s' to '%s'", src, dst);

    string[string] hookEnv = ["DSNAPSHOT_WORK" : dst];

    if (executeHooks("pre_exec", hooks.preExec, hookEnv) != 0)
        throw new SnapshotException(SnapshotException.PreExecFailed.init.SnapshotError);

    logger.infof("%-(%s %)", opts);
    auto syncPid = spawnProcess(opts);

    if (conf.lowPrio) {
        try {
            logger.infof("Changing IO and CPU priority to low (pid %s)", syncPid.processID);
            execute(["ionice", "-c", "3", "-p", syncPid.processID.to!string]);
            execute(["renice", "+12", "-p", syncPid.processID.to!string]);
        } catch (Exception e) {
            logger.info(e.msg);
        }
    }

    if (syncPid.wait != 0)
        throw new SnapshotException(SnapshotException.SyncFailed(src, dst).SnapshotError);

    if (executeHooks("post_exec", hooks.postExec, hookEnv) != 0)
        throw new SnapshotException(SnapshotException.PostExecFailed.init.SnapshotError);
}

void removeLocalSnapshots(const LocalAddr local, const Layout layout) {
    import std.algorithm : map;
    import std.file : rmdirRecurse, exists, isDir;

    foreach (const name; layout.discarded.map!(a => a.name)) {
        const old = (local.value.Path ~ name.value).toString;
        if (exists(old) && old.isDir) {
            logger.info("Removing old snapshot ", old);
            try {
                rmdirRecurse(old);
            } catch (Exception e) {
                logger.warning(e.msg);
            }
        }

    }
}

import dsnapshot.layout : Name, Layout;
import dsnapshot.types : Flow;

auto fillLayout(Layout layout_, Flow flow) {
    import std.algorithm : filter, map, sort;
    import std.array : array;
    import std.conv : to;
    import std.datetime : UTC, DateTimeException, SysTime;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;
    import dsnapshot.layout : LSnapshot = Snapshot;
    import dsnapshot.types : FlowLocal, FlowRsyncToLocal, None;

    auto rval = layout_;
    scope (exit)
        rval.finalize;

    const names = flow.match!((None a) => null,
            (FlowRsyncToLocal a) => snapshotNamesFromDir(a.dst.value.Path),
            (FlowLocal a) => snapshotNamesFromDir(a.dst.value.Path));

    foreach (const n; names) {
        try {
            const t = SysTime.fromISOExtString(n.value, UTC());
            rval.put(LSnapshot(t, n));
        } catch (DateTimeException e) {
            logger.warning("Unable to extract the time from the snapshot name");
            logger.info(e.msg);
            logger.info("It is added as a snapshot taken at the time ", SysTime.min);
            rval.put(LSnapshot(SysTime.min, n));
        }
    }

    return rval;
}

Name[] snapshotNamesFromDir(Path dir) {
    import std.algorithm : filter, map, copy;
    import std.array : appender;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;

    if (!dir.toString.exists)
        return null;
    if (!dir.toString.isDir)
        throw new SnapshotException(SnapshotException.DstIsNotADir.init.SnapshotError);

    auto app = appender!(Name[])();
    dirEntries(dir.toString, SpanMode.shallow).map!(a => a.name)
        .filter!(a => a.isDir)
        .map!(a => Name(a.baseName))
        .copy(app);
    return app.data;
}

@("shall scan the directory for all snapshots")
unittest {
    import std.conv : to;
    import std.datetime : SysTime, UTC, Duration, Clock, dur;
    import std.file;
    import std.path;
    import std.range : enumerate;
    import sumtype;
    import dsnapshot.layout : Layout, LayoutConfig, Span;
    import dsnapshot.types : LocalAddr, FlowLocal, Flow;

    immutable tmpDir = "test_snapshot_scan";
    scope (exit)
        rmdirRecurse(tmpDir);
    mkdir(tmpDir);

    auto curr = Clock.currTime;
    curr.timezone = UTC();

    foreach (const i; 0 .. 15) {
        mkdir(buildPath(tmpDir, curr.toISOExtString));
        curr -= 1.dur!"hours";
    }
    foreach (const i; 0 .. 15) {
        curr -= 5.dur!"hours";
        mkdir(buildPath(tmpDir, curr.toISOExtString));
    }

    auto conf = LayoutConfig([Span(5, 4.dur!"hours"), Span(5, 1.dur!"days")]);
    const base = Clock.currTime;
    auto layout = Layout(base, conf);
    layout = fillLayout(layout, FlowLocal(LocalAddr(tmpDir), LocalAddr(tmpDir)).Flow);

    layout.waiting.length.shouldEqual(0);
    layout.discarded.length.shouldEqual(20);

    (base - layout.snapshotTimeInBucket(0).get).total!"hours".shouldEqual(4);
    (base - layout.snapshotTimeInBucket(4).get).total!"hours".shouldEqual(4 * 5);
    (base - layout.snapshotTimeInBucket(5).get).total!"hours".shouldEqual(4 * 5 + 24 + 1);
    (base - layout.snapshotTimeInBucket(6).get).total!"hours".shouldEqual(4 * 5 + 24 * 2 + 2);
    (base - layout.snapshotTimeInBucket(7).get).total!"hours".shouldEqual(4 * 5 + 24 * 3 - 2);

    /// these buckets are filled by the second  pass
    (base - layout.snapshotTimeInBucket(8).get).total!"hours".shouldEqual(4 * 5 + 24 * 4 - 31);
    (base - layout.snapshotTimeInBucket(9).get).total!"hours".shouldEqual(4 * 5 + 24 * 5 - 60);
}
