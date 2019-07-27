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
    void remoteCmd(const RemoteHost host, const RemoteSubCmd cmd, const string path);

    /// Update layout of the snapshots at the destination in `flow`.
    Layout update(Layout layout);

    /// Publish the snapshot in dst.
    void publishSnapshot(const Flow flow, const string newSnapshot);

    /// Remove discarded snapshots.
    void removeDiscarded(const Flow flow, const Layout layout);
}

final class RsyncBackend : Backend {
    RsyncConfig conf;
    RemoteCmd remoteCmd_;

    this(RsyncConfig conf, RemoteCmd remoteCmd) {
        this.conf = conf;
        this.remoteCmd_ = remoteCmd;
    }

    override void remoteCmd(const RemoteHost host, const RemoteSubCmd cmd_, const string path) {
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

    override void publishSnapshot(const Flow flow, const string newSnapshot) {
        static import dsnapshot.cmdgroup.remote;

        flow.match!((None a) {}, (FlowLocal a) {
            dsnapshot.cmdgroup.remote.publishSnapshot((a.dst.value.Path ~ newSnapshot).toString);
        }, (FlowRsyncToLocal a) {
            dsnapshot.cmdgroup.remote.publishSnapshot((a.dst.value.Path ~ newSnapshot).toString);
        }, (FlowLocalToRsync a) {
            this.remoteCmd(RemoteHost(a.dst.addr, a.dst.path),
                RemoteSubCmd.publishSnapshot, newSnapshot);
        });
    }

    override void removeDiscarded(const Flow flow, const Layout layout) {
        import std.algorithm : map;

        void local(const LocalAddr local) @safe {
            import std.file : rmdirRecurse, exists, isDir;

            foreach (const name; layout.discarded.map!(a => a.name)) {
                const old = (local.value.Path ~ name.value).toString;
                if (exists(old) && old.isDir) {
                    logger.info("Removing old snapshot ", old);
                    try {
                        () @trusted { rmdirRecurse(old); }();
                    } catch (Exception e) {
                        logger.warning(e.msg);
                    }
                }
            }
        }

        void remote(const RemoteHost host) @safe {
            foreach (const name; layout.discarded.map!(a => a.name)) {
                logger.info("Removing old snapshot ", name.value);
                this.remoteCmd(host, RemoteSubCmd.rmdirRecurse, name.value);
            }
        }

        flow.match!((None a) {}, (FlowLocal a) { local(a.dst); }, (FlowRsyncToLocal a) {
            local(a.dst);
        }, (FlowLocalToRsync a) { remote(RemoteHost(a.dst.addr, a.dst.path)); });
    }
}
