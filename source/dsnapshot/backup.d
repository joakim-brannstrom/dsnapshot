/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backup;

import logger = std.experimental.logger;
import std.exception : collectException;

import dsnapshot.config : Config;
import dsnapshot.types : Snapshot, Path;

int cmdBackup(Config.Global global, Config.Backup backup, Snapshot[] snapshots) {
    int exitStatus;

    foreach (const s; snapshots) {
        int snapshotStatus = 1;
        try {
            snapshot(s);
            snapshotStatus = 0;
        } catch (SnapshotException e) {
            logger.error(e.msg);
            final switch (e.status) with (SnapshotStatus) {
            case failed:
                break;
            case ok:
                break;
            case dstIsNotADir:
                logger.error("Destination must be a directory");
                break;
            case unableToAcquireWorkLock:
                logger.errorf("'%s' is locked by another dsnapshot instance", s.dst);
                break;
            case syncFailed:
                logger.errorf("Failed to sync from '%s' to '%s'", s.src, s.dst);
                break;
            }
            logger.error("Failed");
        } catch (Exception e) {
            logger.error(e.msg);
        }

        exitStatus = (snapshotStatus + exitStatus) == 0 ? 0 : 1;
    }

    return exitStatus;
}

class SnapshotException : Exception {
    this(SnapshotStatus s) {
        super(null);
        this.status = s;
    }

    SnapshotStatus status;
}

enum SnapshotStatus {
    failed,
    ok,
    dstIsNotADir,
    unableToAcquireWorkLock,
    syncFailed,
}

private:

/// The directory where a snapshot that is being worked on is put into.
immutable snapshotWork = "work";
/// If the file exists then it means that work is locked.
immutable snapshotWorkLock = "work.lock";

SnapshotStatus snapshot(const Snapshot snapshot) {
    import std.file : exists, mkdirRecurse, rename;
    import std.path : buildPath;

    Path[] snapDirs = scanForSnapshots(snapshot.dst);

    if (!exists(snapshot.dst))
        mkdirRecurse(snapshot.dst);

    auto lock = acquireLock(buildPath(snapshot.dst, snapshotWorkLock).Path);
    const workDir = buildPath(snapshot.dst, snapshotWork);
    mkdirRecurse(workDir);

    sync(snapshot, snapDirs);

    snapDirs = removeOldSnapshots(snapDirs, snapshot.maxNumber);

    incrSnapshotDirs(snapDirs);

    rename(workDir, buildPath(snapshot.dst, "0"));

    return SnapshotStatus.ok;
}

void sync(const Snapshot snapshot, const Path[] snapDirs) {
    import std.path : buildPath;
    import std.process : spawnProcess, wait;

    immutable src = () {
        if (snapshot.src[$ - 1] == '/')
            return snapshot.src;
        return snapshot.src ~ "/";
    }();

    string[] opts = ["rsync"];
    opts ~= snapshot.rsyncArgs.dup;
    if (snapDirs.length != 0)
        opts ~= ["--link-dest", snapDirs[0]];

    opts ~= [src, buildPath(snapshot.dst, snapshotWork)];
    logger.trace(opts);
    logger.infof("Synchronizing '%s' to '%s'", src, snapshot.dst);
    if (spawnProcess(opts).wait != 0)
        throw new SnapshotException(SnapshotStatus.syncFailed);
}

Path[] removeOldSnapshots(Path[] snapDirs, const long maxNumber) {
    import std.file : rmdirRecurse;

    while (snapDirs.length > maxNumber) {
        logger.info("Removing old snapshot ", snapDirs[$ - 1].value);
        rmdirRecurse(snapDirs[$ - 1]);
        snapDirs = snapDirs[0 .. $ - 1];
    }

    return snapDirs;
}

/// Returns: a sorted array from 0 -> X of the directories in dst.
Path[] scanForSnapshots(string dst) {
    import std.algorithm : filter, map, sort;
    import std.array : array;
    import std.conv : to;
    import std.exception : ifThrown;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;

    if (!dst.exists)
        return null;
    if (!dst.isDir)
        throw new SnapshotException(SnapshotStatus.dstIsNotADir);

    return dirEntries(dst, SpanMode.shallow).map!(a => a.name)
        .filter!(a => a.baseName.to!long.ifThrown(-1) >= 0)
        .array
        .sort!((a, b) => a.baseName.to!long < b.baseName.to!long)
        .map!(a => Path(a))
        .array;
}

@("shall scan the directory for all snapshots ")
unittest {
    import std.conv : to;
    import std.file;
    import std.path;

    immutable tmpDir = "test_snapshot_scan";
    scope (exit)
        rmdirRecurse(tmpDir);

    mkdir(tmpDir);
    foreach (i; 0 .. 11)
        mkdir(buildPath(tmpDir, i.to!string));

    auto res = scanForSnapshots(tmpDir);

    logger.info(res);

    assert(res.length == 11);
    assert(res[0].baseName == "0");
    assert(res[$ - 1].baseName == "10");
}

/// This is a blocking operation.
FileLockGuard acquireLock(Path lock) {
    import std.stdio : File;
    import core.thread : getpid;

    auto lockf = File(lock, "w");
    if (!lockf.tryLock)
        throw new SnapshotException(SnapshotStatus.unableToAcquireWorkLock);

    lockf.write(getpid);

    return FileLockGuard(lockf, lock);
}

struct FileLockGuard {
    import std.file : remove;
    import std.stdio : File;

    Path fname;
    File lock;

    this(File lock, Path fname) {
        this.lock = lock;
        this.fname = fname;
    }

    ~this() {
        import std.file : remove;

        lock.close;
        remove(fname);
    }
}

void incrSnapshotDirs(Path[] snaps) {
    import std.conv : to;
    import std.file : rename;
    import std.path : baseName, dirName, buildPath;
    import std.range : retro;

    if (snaps.length == 0)
        return;

    const dir = snaps[0].dirName;

    foreach (const a; snaps.retro) {
        const oldIdx = a.baseName.to!long;
        const new_ = buildPath(dir, (oldIdx + 1).to!string);
        rename(a, new_);
    }
}
