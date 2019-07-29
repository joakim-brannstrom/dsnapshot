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
            return snapshot.syncCmd.match!((const None a) {
                logger.infof("Unable to restore %s (missing command configuration)", snapshot.name);
                return 1;
            }, (const RsyncConfig a) => restore(a, snapshot, conf));
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

int restore(const RsyncConfig conf, SnapshotConfig snapshot, const Config.Restore rconf) {
    import std.file : exists, mkdirRecurse;
    import std.path : buildPath;
    import dsnapshot.console : isInteractiveShell;

    auto backend = makeSyncBackend(snapshot);
    auto crypt = makeCrypBackend(snapshot.crypt);
    open(crypt, backend.flow);
    scope (exit)
        crypt.close;

    // Extract an updated layout of the snapshots at the destination.
    auto layout = snapshot.syncCmd.match!((const None a) => snapshot.layout,
            (const RsyncConfig a) => fillLayout(snapshot.layout, a.flow, snapshot.remoteCmd));

    auto flow = snapshot.syncCmd.match!((const None a) => None.init.Flow,
            (const RsyncConfig a) => a.flow);

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
        opts ~= conf.restoreArgs.dup;

        if (!conf.rsh.empty)
            opts ~= ["-e", conf.rsh];

        if (isInteractiveShell)
            opts ~= conf.progress;

        foreach (a; conf.exclude)
            opts ~= ["--exclude", a];

        flow.match!((None a) {}, (FlowLocal a) {
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
        opts ~= rconf.restoreTo;
        return opts;
    }

    const opts = buildOpts();

    if (!exists(rconf.restoreTo))
        mkdirRecurse(rconf.restoreTo);

    logger.infof("Restoring %s to %s", bestFitSnapshot.name.value, rconf.restoreTo);

    if (spawnProcessLog(opts).wait != 0)
        throw new SnapshotException(SnapshotException.SyncFailed(src,
                rconf.restoreTo).SnapshotError);

    if (conf.useFakeRoot) {
        flow.match!((None a) {}, (FlowLocal a) => fakerootLocalRestore(
                a.dst.value.Path ~ bestFitSnapshot.name.value, rconf.restoreTo),
                (FlowRsyncToLocal a) {
            logger.warning("Restoring permissions to a remote is not supported (yet)");
        }, (FlowLocalToRsync a) => fakerootRemoteRestore(snapshot.remoteCmd,
                a.dst, bestFitSnapshot.name, rconf.restoreTo));
    }

    return 0;
}

void fakerootLocalRestore(const Path root, const string restoreTo) {
    import dsnapshot.stats;

    auto fkdb = fromFakerootEnv(root ~ snapshotFakerootEnv);
    auto pstats = fromFakeroot(fkdb, root.toString, (root ~ snapshotData).toString);
    restorePermissions(pstats, Path(restoreTo));
}

void fakerootRemoteRestore(const RemoteCmd cmd_, const RemoteHost addr,
        const Name name, const string restoreTo) {
    import std.array : appender;
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

void restorePermissions(const from.dsnapshot.stats.PathStat[] pstats, const Path root) {
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
