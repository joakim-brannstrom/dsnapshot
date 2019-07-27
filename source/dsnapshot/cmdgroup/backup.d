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

int cmdBackup(Config.Global global, Config.Backup backup, Snapshot[] snapshots) {
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

void snapshot(Snapshot snapshot, const Config.Backup conf) {
    import std.file : exists, mkdirRecurse, rename;
    import std.path : buildPath, setExtension;
    import std.datetime : Clock;

    auto backend = makeBackend(snapshot);
    auto layout = backend.update(snapshot.layout);

    auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

    logger.trace("Updated layout with information from destination: ", layout);

    const newSnapshot = () {
        if (conf.resume && !layout.resume.isNull) {
            return layout.resume.get.name.value;
        }
        return Clock.currTime.toUTC.toISOExtString ~ snapshotInProgressSuffix;
    }();

    snapshot.syncCmd.match!((None a) {
        logger.info("No sync done for ", snapshot.name, " (missing command configuration)");
    }, (RsyncConfig a) {
        // this ensure that dsnapshot is only executed when there are actual work
        // to do. If multiple snapshots are taken close to each other in time then
        // it means that the "last" one of them is actually the only one that is
        // kept because it is closest to the bucket.
        if (layout.isFirstBucketEmpty) {
            sync(a, layout, flow, snapshot.hooks, snapshot.remoteCmd,
                newSnapshot, conf.ignoreRsyncErrorCodes);
        } else {
            logger.infof("No new snapshot taken because one where recently taken");
            auto first = layout.snapshotTimeInBucket(0);
            if (!first.isNull) {
                logger.infof("Latest snapshot taken at %s. Next snapshot will be taken in %s",
                    first.get, first.get - layout.times[0].begin);
            }
            return;
        }
    });

    backend.publishSnapshot(flow, newSnapshot);
    backend.removeDiscarded(flow, layout);
}

void sync(const RsyncConfig conf, const Layout layout, const Flow flow, const Hooks hooks,
        const RemoteCmd remoteCmd, const string newSnapshot, const int[] ignoreRsyncErrorCodes) {
    import std.algorithm : canFind;
    import std.array : replace, array;
    import std.conv : to;
    import std.file : remove, exists, mkdirRecurse;
    import std.format : format;
    import std.path : buildPath, setExtension;
    import std.process : spawnProcess, wait, execute, spawnShell,
        executeShell, escapeShellFileName;
    import std.stdio : stdin, File;

    static void setupLocalDest(const Path p) {
        auto dst = p ~ snapshotData;
        if (!exists(dst.toString))
            mkdirRecurse(dst.toString);
    }

    static void setupRemoteDest(const RemoteCmd remoteCmd, const RsyncAddr addr,
            const string newSnapshot) {
        string[] cmd = remoteCmd.match!((const SshRemoteCmd a) {
            return a.toCmd(RemoteSubCmd.mkdirRecurse, addr.addr,
                buildPath(addr.path, newSnapshot, snapshotData));
        });
        if (!cmd.empty) {
            logger.infof("%-(%s %)", cmd);
            spawnProcess(cmd).wait;
        }
    }

    static int executeHooks(const string msg, const string[] hooks, const string[string] env) {
        foreach (s; hooks) {
            logger.info(msg, ": ", s);
            if (spawnShell(s, env).wait != 0)
                return 1;
        }
        return 0;
    }

    string src, dst;

    string[] buildOpts() {
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
            flow.match!((None a) {}, (FlowLocal a) {
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
            flow.match!((None a) {}, (FlowLocal a) {
                opts = conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                    (a.dst.value.Path ~ newSnapshot ~ snapshotFakerootEnv).toString)).array ~ opts;
            }, (FlowRsyncToLocal a) {
                opts = conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                    (a.dst.value.Path ~ newSnapshot ~ snapshotFakerootEnv).toString)).array ~ opts;
            }, (FlowLocalToRsync a) {
                opts ~= conf.rsyncFakerootArgs;
                opts ~= format!"%-(%s %) %s"(conf.fakerootArgs.map!(b => b.replace(snapshotFakerootSaveEnvId,
                    buildPath(a.dst.path, newSnapshot, snapshotFakerootEnv))), conf.cmdRsync);
            });
        }

        flow.match!((None a) {}, (FlowLocal a) {
            src = fixRsyncAddr(a.src.value);
            dst = (a.dst.value.Path ~ newSnapshot ~ snapshotData).toString;
            opts ~= [src, dst];
        }, (FlowRsyncToLocal a) {
            src = fixRsyncAddr(makeRsyncAddr(a.src.addr, a.src.path));
            dst = (a.dst.value.Path ~ newSnapshot ~ snapshotData).toString;
            opts ~= [src, dst];
        }, (FlowLocalToRsync a) {
            src = fixRsyncAddr(a.src.value);
            dst = makeRsyncAddr(a.dst.addr, buildPath(a.dst.path, newSnapshot, snapshotData));
            opts ~= [src, dst];
        });

        return opts;
    }

    auto opts = buildOpts();

    // Configure local destination
    flow.match!((None a) {}, (FlowLocal a) => setupLocalDest(a.dst.value.Path ~ newSnapshot),
            (FlowRsyncToLocal a) => setupLocalDest(a.dst.value.Path ~ newSnapshot),
            (FlowLocalToRsync a) => setupRemoteDest(remoteCmd, a.dst, newSnapshot));

    if (src.empty || dst.empty) {
        logger.info("source or destination is empty. Nothing to do.");
        return;
    }

    logger.infof("Synchronizing '%s' to '%s'", src, dst);

    string[string] hookEnv = ["DSNAPSHOT_SRC" : src, "DSNAPSHOT_DST" : dst];

    if (executeHooks("pre_exec", hooks.preExec, hookEnv) != 0)
        throw new SnapshotException(SnapshotException.PreExecFailed.init.SnapshotError);

    logger.infof("%-(%s %)", opts);
    auto syncPid = spawnProcess(opts);

    if (conf.lowPrio) {
        try {
            logger.infof("Changing IO and CPU priority to low (pid %s)", syncPid.processID);
            execute(["ionice", "-c", "3", "-p", syncPid.processID.to!string]);
            execute(["renice", "+12", "-p", syncPid.processID.to!string]);
        } catch (Exception e) {
            logger.info(e.msg);
        }
    }

    auto syncPidExit = syncPid.wait;
    logger.trace("rsync exit code: ", syncPidExit);
    if (syncPidExit != 0 && !canFind(ignoreRsyncErrorCodes, syncPidExit))
        throw new SnapshotException(SnapshotException.SyncFailed(src, dst).SnapshotError);

    if (executeHooks("post_exec", hooks.postExec, hookEnv) != 0)
        throw new SnapshotException(SnapshotException.PostExecFailed.init.SnapshotError);
}
