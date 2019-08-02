/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend.rsync;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.datetime : SysTime;

import dsnapshot.backend.crypt;
import dsnapshot.backend.rsync;
import dsnapshot.backend;
import dsnapshot.config;
import dsnapshot.exception;
import dsnapshot.from;
import dsnapshot.layout : Layout;
import dsnapshot.process;
import dsnapshot.types;

@safe:

final class RsyncBackend : SyncBackend {
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

    override void sync(const Layout layout, const SnapshotConfig snapshot,
            const string nameOfNewSnapshot) {
        import std.algorithm : canFind;
        import std.array : replace, array, empty;
        import std.conv : to;
        import std.file : remove, exists, mkdirRecurse;
        import std.format : format;
        import std.path : buildPath, setExtension;
        import std.process : spawnShell;
        import std.stdio : stdin, File;
        import dsnapshot.console;

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

    override void restore(const Layout layout, const SnapshotConfig snapshot,
            const SysTime time, const string restoreTo) {
        import std.array : empty;
        import std.file : exists, mkdirRecurse;
        import std.path : buildPath;
        import dsnapshot.console : isInteractiveShell;

        const bestFitSnapshot = layout.bestFitBucket(time);
        if (bestFitSnapshot.isNull) {
            logger.error("Unable to find a snapshot to restore for the time ", time);
            throw new SnapshotException(SnapshotException.RestoreFailed(null,
                    restoreTo).SnapshotError);
        }

        string src;

        // TODO: this code is similare to the one in cmdgroup.backup. Consider how
        // it can be deduplicated. Note, similare not the same.
        string[] buildOpts() {
            string[] opts = [conf.cmdRsync];
            opts ~= conf.restoreArgs.dup;

            if (!conf.rsh.empty)
                opts ~= ["-e", conf.rsh];

            if (isInteractiveShell)
                opts ~= conf.progress;

            foreach (a; conf.exclude)
                opts ~= ["--exclude", a];

            conf.flow.match!((None a) {}, (FlowLocal a) {
                src = fixRemteHostForRsync((a.dst.value.Path ~ bestFitSnapshot.name.value ~ snapshotData)
                    .toString);
            }, (FlowRsyncToLocal a) {
                src = fixRemteHostForRsync((a.dst.value.Path ~ bestFitSnapshot.name.value ~ snapshotData)
                    .toString);
            }, (FlowLocalToRsync a) {
                src = makeRsyncAddr(a.dst.addr, fixRemteHostForRsync(buildPath(a.dst.path,
                    bestFitSnapshot.name.value, snapshotData)));
            });

            opts ~= src;
            // dst is always on the local machine as specified by the user
            opts ~= restoreTo;
            return opts;
        }

        const opts = buildOpts();

        if (!exists(restoreTo))
            mkdirRecurse(restoreTo);

        logger.infof("Restoring %s to %s", bestFitSnapshot.name.value, restoreTo);

        if (spawnProcessLog(opts).wait != 0)
            throw new SnapshotException(SnapshotException.RestoreFailed(src,
                    restoreTo).SnapshotError);

        if (conf.useFakeRoot) {
            conf.flow.match!((None a) {}, (FlowLocal a) => fakerootLocalRestore(
                    a.dst.value.Path ~ bestFitSnapshot.name.value, restoreTo), (FlowRsyncToLocal a) {
                logger.warning("Restoring permissions to a remote is not supported (yet)");
            }, (FlowLocalToRsync a) => fakerootRemoteRestore(snapshot.remoteCmd,
                    a.dst, bestFitSnapshot.name, restoreTo));
        }
    }

    Flow flow() {
        return conf.flow;
    }
}

private:

void fakerootLocalRestore(const Path root, const string restoreTo) {
    import dsnapshot.stats;

    auto fkdb = fromFakerootEnv(root ~ snapshotFakerootEnv);
    auto pstats = fromFakeroot(fkdb, root.toString, (root ~ snapshotData).toString);
    restorePermissions(pstats, Path(restoreTo));
}

void fakerootRemoteRestore(const RemoteCmd cmd_, const RemoteHost addr,
        const Name name, const string restoreTo) {
    import std.array : appender, empty;
    import std.path : buildPath;
    import std.string : lineSplitter, strip;
    import dsnapshot.stats;

    auto cmd = cmd_.match!((const SshRemoteCmd a) {
        return a.toCmd(RemoteSubCmd.fakerootStats, addr.addr, buildPath(addr.path, name.value));
    });

    auto res = executeLog(cmd);

    if (res.status != 0) {
        logger.errorf("Unable to restore permissions to %s from %s", restoreTo,
                snapshotFakerootEnv);
        logger.info(res.output);
        return;
    }

    auto app = appender!(PathStat[])();
    foreach (const l; res.output
            .lineSplitter
            .map!(a => a.strip)
            .filter!(a => !a.empty)) {
        try {
            app.put(fromPathStat(l));
        } catch (Exception e) {
            logger.warning("Error when parsing ", l);
            logger.info(e.msg);
        }
    }

    restorePermissions(app.data, Path(restoreTo));
}

void restorePermissions(const from.dsnapshot.stats.PathStat[] pstats, const Path root) @trusted {
    import core.sys.posix.sys.stat : S_IFMT, stat_t, stat, lstat, chmod;
    import core.sys.posix.unistd : chown, lchown;
    import std.file : isFile, isDir, isSymlink;
    import std.string : toStringz;

    foreach (const f; pstats) {
        const curr = (root ~ f.path).toString;
        const currz = curr.toStringz;

        if (curr.isFile || curr.isDir) {
            stat_t st = void;
            stat(currz, &st);
            if (st.st_mode != f.mode) {
                // only set the permissions thus masking out other bits.
                chmod(currz, cast(uint) f.mode & ~S_IFMT);
            }
            if (st.st_uid != f.uid || st.st_gid != f.gid)
                chown(currz, cast(uint) f.uid, cast(uint) f.gid);
        } else if (curr.isSymlink) {
            stat_t st = void;
            lstat(currz, &st);
            if (st.st_uid != f.uid || st.st_gid != f.gid)
                lchown(currz, cast(uint) f.uid, cast(uint) f.gid);
        }
    }
}
