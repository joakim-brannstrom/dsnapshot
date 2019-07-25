/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend;

import logger = std.experimental.logger;

public import dsnapshot.types;
public import dsnapshot.layout : Layout;

@safe:

Backend makeBackend(Snapshot s) {
    import sumtype;

    auto rval = s.syncCmd.match!((None a) => null, (RsyncConfig a) => new RsyncBackend(a,
            s.remoteCmd));

    if (rval is null) {
        throw new Exception("No backend specified. Supported are: rsync");
    }

    return rval;
}

/**
 * Error handling is via exceptions.
 */
interface Backend {
    /// Execute a command on the host that is the destination of the snapshots.
    void remoteCmd(RemoteHost host, RemoteSubCmd cmd, string path);

    /// Update layout of the snapshots at the destination in `flow`.
    Layout update(Layout layout);
}

class RsyncBackend : Backend {
    RsyncConfig conf;
    RemoteCmd remoteCmd_;

    this(RsyncConfig conf, RemoteCmd remoteCmd) {
        this.conf = conf;
        this.remoteCmd_ = remoteCmd;
    }

    override void remoteCmd(RemoteHost host, RemoteSubCmd cmd_, string path) {
        import std.path : buildPath;
        import std.process : spawnProcess, wait;

        auto cmd = remoteCmd_.match!((SshRemoteCmd a) {
            return a.toCmd(cmd_, host.addr, buildPath(host.path, path));
        });
        logger.infof("%-(%s %)", cmd);

        // TODO: throw exception on failure?
        spawnProcess(cmd).wait;
    }

    override Layout update(Layout layout) {
        import dsnapshot.layout_utils;

        return fillLayout(layout, conf.flow, remoteCmd_);
    }
}
