/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.restore;

import logger = std.experimental.logger;
import std.array : empty;
import std.algorithm;
import std.exception : collectException;

import dsnapshot.config : Config;
import dsnapshot.exception;
import dsnapshot.layout_utils;
import dsnapshot.types;

int cmdRestore(Snapshot[] snapshots, const Config.Restore conf) nothrow {
    import dsnapshot.layout;
    import dsnapshot.layout_utils;

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
            return snapshot.syncCmd.match!((None a) {
                logger.infof("Unable to restore %s (missing command configuration)", snapshot.name);
                return 1;
            }, (RsyncConfig a) => restore(a, snapshot, conf));
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

int restore(const RsyncConfig conf, Snapshot snapshot, const Config.Restore rconf) {
    import std.file : exists, mkdirRecurse;
    import std.path : buildPath;
    import std.process : spawnProcess, wait;
    import dsnapshot.console : isInteractiveShell;

    // Extract an updated layout of the snapshots at the destination.
    auto layout = snapshot.syncCmd.match!((None a) => snapshot.layout,
            (RsyncConfig a) => fillLayout(snapshot.layout, a.flow, snapshot.remoteCmd));

    auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

    const bestFitSnapshot = layout.bestFitBucket(rconf.time);
    if (bestFitSnapshot.isNull) {
        logger.error("Unable to find a snapshot to restore for the time ", rconf.time);
        return 1;
    }

    string src;

    // TODO: this code is similare to the one in cmdgroup.backup. Consider how
    // it can be deduplicated. Note, similare not the same.
    string[] buildOpts() {
        string[] opts = [conf.cmdRsync];
        opts ~= conf.args.dup;

        if (!conf.rsh.empty)
            opts ~= ["-e", conf.rsh];

        if (isInteractiveShell)
            opts ~= conf.progress;

        foreach (a; conf.exclude)
            opts ~= ["--exclude", a];

        flow.match!((None a) {}, (FlowLocal a) {
            src = fixRsyncAddr((a.dst.value.Path ~ bestFitSnapshot.name.value).toString);
        }, (FlowRsyncToLocal a) {
            src = fixRsyncAddr((a.dst.value.Path ~ bestFitSnapshot.name.value).toString);
        }, (FlowLocalToRsync a) {
            src = makeRsyncAddr(a.dst.addr, fixRsyncAddr(buildPath(a.dst.path,
                bestFitSnapshot.name.value)));
        });

        opts ~= src;
        // dst is always on the local machine as specified by the user
        opts ~= rconf.restoreTo;
        return opts;
    }

    const opts = buildOpts();

    if (!exists(rconf.restoreTo))
        mkdirRecurse(rconf.restoreTo);

    logger.infof("Restoring %s to %s", bestFitSnapshot.name.value, rconf.restoreTo);

    logger.infof("%-(%s %)", opts);
    if (spawnProcess(opts).wait != 0)
        throw new SnapshotException(SnapshotException.SyncFailed(src,
                rconf.restoreTo).SnapshotError);

    return 0;
}
