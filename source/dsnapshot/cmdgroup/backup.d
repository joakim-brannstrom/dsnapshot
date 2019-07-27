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

int cmdBackup(Config.Global global, Config.Backup backup, Snapshot[] snapshots) {
    int exitStatus;

    foreach (s; snapshots.filter!(a => backup.name.value.empty || backup.name.value == a.name)) {
        int snapshotStatus = 1;
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

void snapshot(Snapshot snapshot, const Config.Backup conf) {
    import std.datetime : Clock;

    auto backend = makeBackend(snapshot, conf);
    auto layout = backend.update(snapshot.layout);

    auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

    logger.trace("Updated layout with information from destination: ", layout);

    const newSnapshot = () {
        if (conf.resume && !layout.resume.isNull) {
            return layout.resume.get.name.value;
        }
        return Clock.currTime.toUTC.toISOExtString ~ snapshotInProgressSuffix;
    }();

    backend.sync(flow, layout, snapshot, newSnapshot);

    backend.publishSnapshot(flow, newSnapshot);
    backend.removeDiscarded(flow, layout);
}
