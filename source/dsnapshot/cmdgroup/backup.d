/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.backup;

import logger = std.experimental.logger;
import std.array : empty;
import std.exception : collectException;
import std.algorithm : filter, map;

import sumtype;

import dsnapshot.config : Config;
import dsnapshot.types;

import dsnapshot.exception;
import dsnapshot.layout : Name, Layout;
import dsnapshot.layout_utils;
import dsnapshot.console;
import dsnapshot.backend;

version (unittest) {
    import unit_threaded.assertions;
}

int cmdBackup(Config.Global global, Config.Backup backup, SnapshotConfig[] snapshots) {
    int exitStatus;

    foreach (s; snapshots.filter!(a => backup.name.value.empty || backup.name.value == a.name)) {
        int snapshotStatus = 1;
        logger.info("# Start snapshot ", s.name);
        scope (exit)
            logger.info("# Done snapshot ", s.name);

        try {
            snapshot(s, backup);
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

private:

void snapshot(SnapshotConfig snapshot, const Config.Backup conf) {
    import std.datetime : Clock;

    auto backend = makeSyncBackend(snapshot, conf);

    auto crypt = makeCrypBackend(snapshot.crypt);
    open(crypt, backend.flow);
    scope (exit)
        crypt.close;

    auto layout = backend.update(snapshot.layout);
    logger.trace("Updated layout with information from destination: ", layout);

    // this ensure that dsnapshot is only executed when there are actual work
    // to do. If multiple snapshots are taken close to each other in time then
    // it means that the "last" one of them is actually the only one that is
    // kept because it is closest to the bucket.
    if (!layout.isFirstBucketEmpty) {
        const first = layout.snapshotTimeInBucket(0);
        const timeLeft = first.get - layout.times[0].begin;
        if (timeLeft > conf.newSnapshotMargin) {
            logger.infof("No new snapshot taken because one where recently taken");

            if (!first.isNull) {
                logger.infof("Latest snapshot taken at %s. Next snapshot will be taken in %s",
                        first.get, timeLeft);
            }
            return;
        }
    }

    const newSnapshot = () {
        if (conf.resume && !layout.resume.isNull) {
            return layout.resume.get.name.value;
        }
        return Clock.currTime.toUTC.toISOExtString ~ snapshotInProgressSuffix;
    }();

    backend.sync(layout, snapshot, newSnapshot);

    backend.publishSnapshot(newSnapshot);
    backend.removeDiscarded(layout);
}
