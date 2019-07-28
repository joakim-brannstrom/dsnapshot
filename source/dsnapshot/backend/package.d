/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend;

import logger = std.experimental.logger;
import std.algorithm : map, filter;

import dsnapshot.process;
import dsnapshot.config;
import dsnapshot.exception;
public import dsnapshot.layout : Layout;
public import dsnapshot.types;

@safe:

Backend makeBackend(Snapshot s, const dsnapshot.config.Config.Backup backup) {
    auto rval = s.syncCmd.match!((None a) { return null; },
            (RsyncConfig a) => new RsyncBackend(a, s.remoteCmd, backup.ignoreRsyncErrorCodes));

    if (rval is null) {
        logger.infof("No backend specified for %s. Supported are: rsync", s.name);
        throw new Exception(null);
    }
    return rval;
}

/**
 * Error handling is via exceptions.
 */
interface Backend {
    /// Execute a command on the host that is the destination of the snapshots.
    void remoteCmd(const RemoteHost host, const RemoteSubCmd cmd, const string path);

    /// Update layout of the snapshots at the destination.
    Layout update(Layout layout);

    /// Publish the snapshot in dst.
    void publishSnapshot(const string newSnapshot);

    /// Remove discarded snapshots.
    void removeDiscarded(const Layout layout);

    /// Sync from src to dst.
    void sync(const Layout layout, const Snapshot snapshot, const string nameOfNewSnapshot);
}

final class RsyncBackend : Backend {
    RsyncConfig conf;
    RemoteCmd remoteCmd_;
    /// Error codes ignored when Synchronizing.
    const(int)[] ignoreRsyncErrorCodes;

    this(RsyncConfig conf, RemoteCmd remoteCmd, const(int)[] ignoreRsyncErrorCodes) {
        this.conf = conf;
        this.remoteCmd_ = remoteCmd;
        this.ignoreRsyncErrorCodes = ignoreRsyncErrorCodes;
    }

    override void remoteCmd(const RemoteHost host, const RemoteSubCmd cmd_, const string path) {
        import std.path : buildPath;

        auto cmd = remoteCmd_.match!((SshRemoteCmd a) {
            return a.toCmd(cmd_, host.addr, buildPath(host.path, path));
        });

        // TODO: throw exception on failure?
        spawnProcessLog(cmd).wait;
    }

    override Layout update(Layout layout) {
        import dsnapshot.layout_utils;

        return fillLayout(layout, conf.flow, remoteCmd_);
    }

    override void publishSnapshot(const string newSnapshot) {
        static import dsnapshot.cmdgroup.remote;

        conf.flow.match!((None a) {}, (FlowLocal a) {
            dsnapshot.cmdgroup.remote.publishSnapshot((a.dst.value.Path ~ newSnapshot).toString);
        }, (FlowRsyncToLocal a) {
            dsnapshot.cmdgroup.remote.publishSnapshot((a.dst.value.Path ~ newSnapshot).toString);
        }, (FlowLocalToRsync a) {
            this.remoteCmd(RemoteHost(a.dst.addr, a.dst.path),
                RemoteSubCmd.publishSnapshot, newSnapshot);
        });
    }

    override void removeDiscarded(const Layout layout) {
        void local(const LocalAddr local) @safe {
            import std.file : rmdirRecurse, exists, isDir;

            foreach (const old; layout.discarded
                    .map!(a => (local.value.Path ~ a.name.value).toString)
                    .filter!(a => exists(a) && a.isDir)) {
                logger.info("Removing old snapshot ", old);
                try {
                    () @trusted { rmdirRecurse(old); }();
                } catch (Exception e) {
                    logger.warning(e.msg);
                }
            }
        }

        void remote(const RemoteHost host) @safe {
            foreach (const name; layout.discarded.map!(a => a.name)) {
                logger.info("Removing old snapshot ", name.value);
                this.remoteCmd(host, RemoteSubCmd.rmdirRecurse, name.value);
            }
        }

        conf.flow.match!((None a) {}, (FlowLocal a) { local(a.dst); }, (FlowRsyncToLocal a) {
            local(a.dst);
        }, (FlowLocalToRsync a) { remote(RemoteHost(a.dst.addr, a.dst.path)); });
    }

    override void sync(const Layout layout, const Snapshot snapshot, const string nameOfNewSnapshot) {
        import std.algorithm : canFind;
        import std.array : replace, array, empty;
        import std.conv : to;
        import std.file : remove, exists, mkdirRecurse;
        import std.format : format;
        import std.path : buildPath, setExtension;
        import std.process : spawnShell;
        import std.stdio : stdin, File;
        import dsnapshot.console;

        // this ensure that dsnapshot is only executed when there are actual work
        // to do. If multiple snapshots are taken close to each other in time then
        // it means that the "last" one of them is actually the only one that is
        // kept because it is closest to the bucket.
        if (!layout.isFirstBucketEmpty) {
            logger.infof("No new snapshot taken because one where recently taken");
            auto first = layout.snapshotTimeInBucket(0);
            if (!first.isNull) {
                logger.infof("Latest snapshot taken at %s. Next snapshot will be taken in %s",
                        first.get, first.get - layout.times[0].begin);
            }
            return;
        }

        static void setupLocalDest(const Path p) @safe {
            auto dst = p ~ snapshotData;
            if (!exists(dst.toString))
                mkdirRecurse(dst.toString);
        }

        static void setupRemoteDest(const RemoteCmd remoteCmd,
                const RemoteHost addr, const string newSnapshot) @safe {
            string[] cmd = remoteCmd.match!((const SshRemoteCmd a) {
                return a.toCmd(RemoteSubCmd.mkdirRecurse, addr.addr,
                    buildPath(addr.path, newSnapshot, snapshotData));
            });
            if (!cmd.empty) {
                spawnProcessLog(cmd).wait;
            }
        }

        static int executeHooks(const string msg, const string[] hooks, const string[string] env) @safe {
            foreach (s; hooks) {
                logger.info(msg, ": ", s);
                if (spawnShell(s, env).wait != 0)
                    return 1;
            }
            return 0;
        }

        string src, dst;

        string[] buildOpts() @safe {
            string[] opts = [conf.cmdRsync];
            opts ~= conf.backupArgs.dup;

            const latest = layout.firstFullBucket;

            if (!conf.rsh.empty)
                opts ~= ["-e", conf.rsh];

            if (isInteractiveShell)
                opts ~= conf.progress;

            if (conf.oneFs && !latest.isNull)
                opts ~= ["-x"];

            if (conf.useLinkDest && !latest.isNull) {
                conf.flow.match!((None a) {}, (FlowLocal a) {
                    opts ~= [
                        "--link-dest",
                        (a.dst.value.Path ~ latest.get.name.value ~ snapshotData).toString
                    ];
                }, (FlowRsyncToLocal a) {
                    opts ~= [
                        "--link-dest",
                        (a.dst.value.Path ~ latest.get.name.value ~ snapshotData).toString
                    ];
                }, (FlowLocalToRsync a) {
                    // from the rsync documentation:
                    // If DIR is a relative path, it is relative to the destination directory.
                    opts ~= [
                        "--link-dest",
                        buildPath("..", "..", latest.get.name.value, snapshotData)
                    ];
                });
            }

            foreach (a; conf.exclude)
                opts ~= ["--exclude", a];

            if (conf.useFakeRoot) {
                conf.flow.match!((None a) {}, (FlowLocal a) {
                    opts = conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                        (a.dst.value.Path ~ nameOfNewSnapshot ~ snapshotFakerootEnv).toString)).array
                        ~ opts;
                }, (FlowRsyncToLocal a) {
                    opts = conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                        (a.dst.value.Path ~ nameOfNewSnapshot ~ snapshotFakerootEnv).toString)).array
                        ~ opts;
                }, (FlowLocalToRsync a) {
                    opts ~= conf.rsyncFakerootArgs;
                    opts ~= format!"%-(%s %) %s"(conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                        buildPath(a.dst.path, nameOfNewSnapshot, snapshotFakerootEnv))),
                        conf.cmdRsync);
                });
            }

            conf.flow.match!((None a) {}, (FlowLocal a) {
                src = fixRemteHostForRsync(a.src.value);
                dst = (a.dst.value.Path ~ nameOfNewSnapshot ~ snapshotData).toString;
                opts ~= [src, dst];
            }, (FlowRsyncToLocal a) {
                src = fixRemteHostForRsync(makeRsyncAddr(a.src.addr, a.src.path));
                dst = (a.dst.value.Path ~ nameOfNewSnapshot ~ snapshotData).toString;
                opts ~= [src, dst];
            }, (FlowLocalToRsync a) {
                src = fixRemteHostForRsync(a.src.value);
                dst = makeRsyncAddr(a.dst.addr, buildPath(a.dst.path,
                    nameOfNewSnapshot, snapshotData));
                opts ~= [src, dst];
            });

            return opts;
        }

        auto opts = buildOpts();

        if (src.empty || dst.empty) {
            logger.info("source or destination is not configured. Nothing to do.");
            return;
        }

        // Configure local destination
        conf.flow.match!((None a) {}, (FlowLocal a) => setupLocalDest(a.dst.value.Path ~ nameOfNewSnapshot),
                (FlowRsyncToLocal a) => setupLocalDest(a.dst.value.Path ~ nameOfNewSnapshot),
                (FlowLocalToRsync a) => setupRemoteDest(remoteCmd_, a.dst, nameOfNewSnapshot));

        logger.infof("Synchronizing '%s' to '%s'", src, dst);

        string[string] hookEnv = ["DSNAPSHOT_SRC" : src, "DSNAPSHOT_DST" : dst];

        if (executeHooks("pre_exec", snapshot.hooks.preExec, hookEnv) != 0)
            throw new SnapshotException(SnapshotException.PreExecFailed.init.SnapshotError);

        auto syncPid = spawnProcessLog(opts);

        if (conf.lowPrio) {
            try {
                logger.infof("Changing IO and CPU priority to low (pid %s)", syncPid.processID);
                executeLog([
                        "ionice", "-c", "3", "-p", syncPid.processID.to!string
                        ]);
                executeLog(["renice", "+12", "-p", syncPid.processID.to!string]);
            } catch (Exception e) {
                logger.info(e.msg);
            }
        }

        auto syncPidExit = syncPid.wait;
        logger.trace("rsync exit code: ", syncPidExit);
        if (syncPidExit != 0 && !canFind(ignoreRsyncErrorCodes, syncPidExit))
            throw new SnapshotException(SnapshotException.SyncFailed(src, dst).SnapshotError);

        if (executeHooks("post_exec", snapshot.hooks.postExec, hookEnv) != 0)
            throw new SnapshotException(SnapshotException.PostExecFailed.init.SnapshotError);
    }
}
