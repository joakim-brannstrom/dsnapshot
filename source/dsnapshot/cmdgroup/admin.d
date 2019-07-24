/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.admin;

import logger = std.experimental.logger;
import std.algorithm;
import std.array : empty, array;
import std.exception : collectException;
import std.process : spawnProcess, wait;
import std.stdio : writeln;

import dsnapshot.config : Config;
import dsnapshot.exception;
import dsnapshot.types;

@safe:

int cmdAdmin(Snapshot[] snapshots, const Config.Admin conf) nothrow {
    auto operateOn = () {
        if (conf.names.empty) {
            return snapshots;
        }

        import dsnapshot.set : Set, toSet;

        Set!string pick = conf.names.map!(a => a.value).toSet;
        return snapshots.filter!(a => pick.contains(a.name)).array;
    }();

    foreach (snapshot; operateOn) {
        auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

        try {
            final switch (conf.cmd) with (Config.Admin) {
            case Cmd.list:
                cmdList(snapshot, flow);
                break;
            case Cmd.diskusage:
                cmdDiskUsage(snapshot, flow);
                break;
            }
        } catch (SnapshotException e) {
            e.errMsg.match!(a => a.print).collectException;
            logger.error(e.msg).collectException;
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            break;
        }
    }

    return 0;
}

private:

void cmdList(Snapshot snapshot, Flow flow) {
    import dsnapshot.layout_utils;

    auto layout = snapshot.syncCmd.match!((None a) => snapshot.layout,
            (RsyncConfig a) => fillLayout(snapshot.layout, a.flow, snapshot.remoteCmd));

    writeln("Snapshot config: ", snapshot.name);
    writeln(layout);
}

void cmdDiskUsage(Snapshot snapshot, Flow flow) {
    import dsnapshot.layout;
    import dsnapshot.layout_utils;

    writeln("Snapshot config: ", snapshot.name);

    const cmdDu = snapshot.syncCmd.match!((None a) => null, (RsyncConfig a) => a.cmdDiskUsage);
    if (cmdDu.empty) {
        logger.errorf("cmd_du is not set for snapshot %s", snapshot.name).collectException;
        return;
    }

    // dfmt off
    flow.match!((None a) => 1,
                       (FlowRsyncToLocal a) => localDiskUsage(cmdDu, a.dst.value.Path),
                       (FlowLocal a) => localDiskUsage(cmdDu, a.dst.value.Path),
                       (FlowLocalToRsync a) => remoteDiskUsage(a.dst, snapshot.remoteCmd, cmdDu)
                       );
    // dfmt on
}

int localDiskUsage(const string[] cmdDu, Path p) {
    auto cmd = cmdDu ~ p.toString;
    logger.infof("%-(%s %)", cmd);
    return spawnProcess(cmd).wait;
}

int remoteDiskUsage(RsyncAddr addr, RemoteCmd remote, const string[] cmdDu) {
    auto cmd = remote.match!((SshRemoteCmd a) => a.rsh);
    cmd ~= addr.addr ~ cmdDu ~ addr.path;
    logger.infof("%-(%s %)", cmd);
    return spawnProcess(cmd).wait;
}
