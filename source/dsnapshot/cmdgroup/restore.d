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
import dsnapshot.types;

int cmdRestore(Snapshot[] snapshots, const Config.Restore conf) nothrow {
    import dsnapshot.layout;
    import dsnapshot.layout_utils;

    //if (conf.name.value.empty) {
    //    logger.error("No snapshot name specified (-s|--snapshot)").collectException;
    //    return 1;
    //}
    //
    //foreach (snapshot; snapshots.filter!(a => a.name == conf.name.value)) {
    //    const cmdDu = snapshot.syncCmd.match!((None a) => null, (RsyncConfig a) => a.cmdDiskUsage);
    //    if (cmdDu.empty) {
    //        logger.errorf("cmd_du is not set for snapshot %s", snapshot.name).collectException;
    //        return 1;
    //    }
    //
    //    try {
    //        auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a
    //                .flow);
    //        // dfmt off
    //        return flow.match!((None a) => 1,
    //                           (FlowRsyncToLocal a) => localDiskUsage(cmdDu, a.dst.value.Path),
    //                           (FlowLocal a) => localDiskUsage(cmdDu, a.dst.value.Path),
    //                           (FlowLocalToRsync a) => remoteDiskUsage(a.dst, snapshot.remoteCmd, cmdDu)
    //                           );
    //        // dfmt on
    //    } catch (SnapshotException e) {
    //        e.errMsg.match!(a => a.print).collectException;
    //        logger.error(e.msg).collectException;
    //    } catch (Exception e) {
    //        logger.error(e.msg).collectException;
    //        break;
    //    }
    //}
    //
    //logger.errorf("No snapshot with the name %s found", conf.name.value).collectException;
    //logger.infof("Available snapshots are: %-(%s, %)",
    //        snapshots.map!(a => a.name)).collectException;
    return 1;
}

//int localDiskUsage(const string[] cmdDu, Path p) {
//    import std.process : spawnProcess, wait;
//
//    auto cmd = cmdDu ~ p.toString;
//    logger.infof("%-(%s %)", cmd);
//    return spawnProcess(cmd).wait;
//}
//
//int remoteDiskUsage(RsyncAddr addr, RemoteCmd remote, const string[] cmdDu) {
//    import std.process : spawnProcess, wait;
//
//    auto cmd = remote.match!((SshRemoteCmd a) => a.rsh);
//    cmd ~= addr.addr ~ cmdDu ~ addr.path;
//    logger.infof("%-(%s %)", cmd);
//    return spawnProcess(cmd).wait;
//}
