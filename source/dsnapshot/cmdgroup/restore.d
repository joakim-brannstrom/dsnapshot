/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.restore;

import logger = std.experimental.logger;
import std.algorithm : map, filter, canFind;
import std.array : empty, array;
import std.exception : collectException;

import dsnapshot.backend;
import dsnapshot.config : Config;
import dsnapshot.exception;
import dsnapshot.from;
import dsnapshot.layout_utils;
import dsnapshot.process;
import dsnapshot.types;

version (unittest) {
    import unit_threaded.assertions;
}

int cmdRestore(SnapshotConfig[] snapshots, const Config.Restore conf) nothrow {
    import dsnapshot.layout;

    if (conf.name.value.empty) {
        logger.error("No snapshot name specified (-s|--snapshot)").collectException;
        return 1;
    }
    if (conf.restoreTo.empty) {
        logger.error("No destination is specified (--dst)").collectException;
        return 1;
    }

    foreach (snapshot; snapshots.filter!(a => a.name == conf.name.value)) {
        try {
            return restore(snapshot, conf);
        } catch (SnapshotException e) {
            e.errMsg.match!(a => a.print).collectException;
            logger.error(e.msg).collectException;
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            break;
        }
    }

    logger.errorf("No snapshot with the name %s found", conf.name.value).collectException;
    logger.infof("Available snapshots are: %-(%s, %)",
            snapshots.map!(a => a.name)).collectException;
    return 1;
}

private:

int restore(SnapshotConfig snapshot, const Config.Restore rconf) {
    auto backend = makeSyncBackend(snapshot);

    auto crypt = makeCrypBackend(snapshot.crypt);
    open(crypt, backend.flow);
    scope (exit)
        crypt.close;

    // Extract an updated layout of the snapshots at the destination.
    auto layout = backend.update(snapshot.layout);
    logger.trace("Updated layout with information from destination: ", layout);

    backend.restore(layout, snapshot, rconf.time, rconf.restoreTo);

    return 0;
}
