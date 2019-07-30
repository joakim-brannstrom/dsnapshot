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
