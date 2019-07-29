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
import std.stdio : writeln;

import dsnapshot.backend;
import dsnapshot.config : Config;
import dsnapshot.exception;
import dsnapshot.process;
import dsnapshot.types;

@safe:

int cmdAdmin(SnapshotConfig[] snapshots, const Config.Admin conf) nothrow {
    auto operateOn = () {
        if (conf.names.empty) {
            return snapshots;
        }

        import dsnapshot.set : Set, toSet;

        Set!string pick = conf.names.map!(a => a.value).toSet;
        return snapshots.filter!(a => pick.contains(a.name)).array;
    }();

    foreach (snapshot; operateOn) {
        try {
            auto backend = makeSyncBackend(snapshot);

            auto crypt = makeCrypBackend(snapshot.crypt);
            open(crypt, backend.flow);
            scope (exit)
                crypt.close;

            final switch (conf.cmd) with (Config.Admin) {
            case Cmd.list:
                cmdList(snapshot, backend.flow);
                break;
            case Cmd.diskusage:
                cmdDiskUsage(snapshot, backend.flow);
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

void cmdList(SnapshotConfig snapshot, Flow flow) {
    import dsnapshot.layout_utils;

    auto layout = snapshot.syncCmd.match!((None a) => snapshot.layout,
            (RsyncConfig a) => fillLayout(snapshot.layout, a.flow, snapshot.remoteCmd));

    writeln("Snapshot config: ", snapshot.name);
    writeln(layout);
}

void cmdDiskUsage(SnapshotConfig snapshot, Flow flow) {
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
    return spawnProcessLog(cmdDu ~ p.toString).wait;
}

int remoteDiskUsage(RemoteHost host, RemoteCmd remote, const string[] cmdDu) {
    auto cmd = remote.match!((SshRemoteCmd a) => a.rsh);
    cmd ~= host.addr ~ cmdDu ~ host.path;
    return spawnProcessLog(cmd).wait;
}
