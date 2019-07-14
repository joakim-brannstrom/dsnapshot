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

import sumtype;

version (unittest) {
    import unit_threaded.assertions;
}

int cmdBackup(Config.Global global, Config.Backup backup, Snapshot[] snapshots) {
    int exitStatus;

    foreach (s; snapshots) {
        int snapshotStatus = 1;
        try {
            snapshot(s);
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

class SnapshotException : Exception {
    this(SnapshotError s) {
        super(null);
        this.errMsg = s;
    }

    SnapshotError errMsg;

    static struct DstIsNotADir {
        void print() {
            logger.error("Destination must be a directory");
        }
    }

    static struct UnableToAcquireWorkLock {
        string dst;
        void print() {
            logger.errorf("'%s' is locked by another dsnapshot instance", dst);
        }
    }

    static struct SyncFailed {
        string src;
        string dst;
        void print() {
            logger.errorf("Failed to sync from '%s' to '%s'", src, dst);
        }
    }

    static struct PreExecFailed {
        void print() {
            logger.error("One or more of the `pre_exec` hooks failed");
        }
    }

    static struct PostExecFailed {
        void print() {
            logger.error("One or more of the `post_exec` hooks failed");
        }
    }
}

alias SnapshotError = SumType!(SnapshotException.DstIsNotADir, SnapshotException.UnableToAcquireWorkLock,
        SnapshotException.SyncFailed, SnapshotException.PreExecFailed,
        SnapshotException.PostExecFailed,);

private:

/// The directory where a snapshot that is being worked on is put into.
immutable snapshotWork = "work";
/// If the file exists then it means that work is locked.
immutable snapshotWorkLock = "work.lock";
/// Extension used for rsync logs
immutable snapshotLog = ".log";

void snapshot(Snapshot snapshot) {
    import std.file : exists, mkdirRecurse, rename;
    import std.path : buildPath, setExtension;

    //Path[] snapDirs = scanForSnapshots(snapshot.dst);
    //
    //if (!exists(snapshot.dst))
    //    mkdirRecurse(snapshot.dst);
    //
    //auto lock = acquireLock(buildPath(snapshot.dst, snapshotWorkLock).Path);
    //const workDir = buildPath(snapshot.dst, snapshotWork);
    //mkdirRecurse(workDir);
    //
    //auto layout = fillLayout(snapshot);
    //logger.trace("Filled layout: ", layout);

    //sync(snapshot, snapDirs);

    //snapDirs = removeOldSnapshots(snapDirs, snapshot.maxNumber);
    //
    //incrSnapshotDirs(snapDirs);
    //
    //rename(workDir, buildPath(snapshot.dst, "0"));
    //rename(workDir.setExtension(snapshotLog), buildPath(snapshot.dst, "0")
    //        .setExtension(snapshotLog));
}

//void sync(const Snapshot snapshot, const Path[] snapDirs) {
//    import std.conv : to;
//    import std.file : remove;
//    import std.path : buildPath, setExtension;
//    import std.process : spawnProcess, wait, execute, spawnShell, executeShell;
//    import std.stdio : stdin, File;
//
//    immutable src = () {
//        if (snapshot.src[$ - 1] == '/')
//            return snapshot.src;
//        return snapshot.src ~ "/";
//    }();
//
//    string[] opts = [snapshot.cmdRsync];
//    opts ~= snapshot.rsyncArgs.dup;
//
//    if (snapshot.oneFs)
//        opts ~= ["-x"];
//
//    if (snapshot.useLinkDest && snapDirs.length != 0)
//        opts ~= ["--link-dest", snapDirs[0].toString];
//
//    foreach (a; snapshot.exclude)
//        opts ~= ["--exclude", a];
//
//    const workDir = buildPath(snapshot.dst, snapshotWork);
//    const logFname = workDir.setExtension(snapshotLog);
//
//    opts ~= [src, workDir];
//
//    logger.trace(opts);
//    logger.infof("Synchronizing '%s' to '%s'", src, snapshot.dst);
//
//    string[string] hookEnv = ["DSNAPSHOT_WORK" : workDir];
//
//    // execute hook
//    auto log = File(logFname, "w");
//    foreach (s; snapshot.preExec) {
//        logger.trace("pre_exec: ", s);
//        if (spawnShell(s, stdin, log, log, hookEnv).wait != 0)
//            throw new SnapshotException(SnapshotStatus.preExecFailed);
//    }
//
//    log = File(logFname, "a");
//    log.writefln("%-(%s %)", opts);
//
//    log = File(logFname, "a");
//    auto syncPid = spawnProcess(opts, stdin, log, log);
//
//    if (snapshot.lowPrio) {
//        try {
//            logger.info("Changing IO and CPU priority to low");
//            execute(["ionice", "-c", "3", "-p", syncPid.processID.to!string]);
//            execute(["renice", "+12", "-p", syncPid.processID.to!string]);
//        } catch (Exception e) {
//            logger.info(e.msg);
//        }
//    }
//
//    if (syncPid.wait != 0)
//        throw new SnapshotException(SnapshotStatus.syncFailed);
//
//    // execute hook
//    log = File(logFname, "a");
//    foreach (s; snapshot.postExec) {
//        logger.trace("post_exec: ", s);
//        if (spawnShell(s, stdin, log, log, hookEnv).wait != 0)
//            throw new SnapshotException(SnapshotStatus.postExecFailed);
//    }
//}
//
//Path[] removeOldSnapshots(Path[] snapDirs, const long maxNumber) {
//    import std.file : rmdirRecurse, remove;
//    import std.path : setExtension;
//
//    while (snapDirs.length > maxNumber) {
//        const old = snapDirs[$ - 1];
//        logger.info("Removing old snapshot ", old);
//        rmdirRecurse(old.toString);
//        remove(old.toString.setExtension(snapshotLog)).collectException;
//        snapDirs = snapDirs[0 .. $ - 1];
//    }
//
//    return snapDirs;
//}

import dsnapshot.layout : Name, Layout;
import dsnapshot.types : Flow;

auto fillLayout(Layout layout_, Flow flow) {
    import std.algorithm : filter, map, sort;
    import std.array : array;
    import std.conv : to;
    import std.datetime : UTC, DateTimeException, SysTime;
    import std.exception : ifThrown;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;
    import dsnapshot.layout : LSnapshot = Snapshot;
    import dsnapshot.types : FlowLocal, FlowRsyncToLocal, None;

    auto rval = layout_;

    const names = flow.match!((None a) => null,
            (FlowRsyncToLocal a) => snapshotNamesFromDir(a.dst.value.Path),
            (FlowLocal a) => snapshotNamesFromDir(a.dst.value.Path));

    foreach (const n; names) {
        try {
            const t = SysTime.fromISOExtString(n.value, UTC());
            rval.put(LSnapshot(t, n));
        } catch (DateTimeException e) {
            logger.warning("Unable to extract the time from the snapshot name");
            logger.info("It is added as a snapshot taken at the time ", SysTime.min);
            logger.info(e.msg);
            rval.put(LSnapshot(SysTime.min, n));
        }
    }

    return rval;
}

Name[] snapshotNamesFromDir(Path dir) {
    import std.algorithm : filter, map, copy;
    import std.array : appender;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;

    if (!dir.toString.exists)
        return null;
    if (!dir.toString.isDir)
        throw new SnapshotException(SnapshotException.DstIsNotADir.init.SnapshotError);

    auto app = appender!(Name[])();
    dirEntries(dir.toString, SpanMode.shallow).map!(a => a.name)
        .filter!(a => a.isDir)
        .map!(a => Name(a.baseName))
        .copy(app);
    return app.data;
}

@("shall scan the directory for all snapshots")
unittest {
    import std.conv : to;
    import std.datetime : SysTime, UTC, Duration, Clock, dur;
    import std.file;
    import std.path;
    import std.range : enumerate;
    import dsnapshot.layout : Layout, LayoutConfig, Span;
    import dsnapshot.types : LocalAddr, FlowLocal, Flow;

    immutable tmpDir = "test_snapshot_scan";
    scope (exit)
        rmdirRecurse(tmpDir);
    mkdir(tmpDir);

    immutable interval = 1.dur!"hours";
    auto curr = Clock.currTime;
    curr.timezone = UTC();

    foreach (const i; 0 .. 39) {
        mkdir(buildPath(tmpDir, curr.toISOExtString));
        curr -= interval;
    }

    auto conf = LayoutConfig([Span(5, 4.dur!"hours"), Span(5, 1.dur!"days")]);
    const base = Clock.currTime;
    auto layout = Layout(base, conf);
    layout = fillLayout(layout, FlowLocal(LocalAddr(tmpDir), LocalAddr(tmpDir)).Flow);

    // 39 added, 6 are used
    layout.discarded.length.shouldEqual(33);

    (base - layout.time[0]).total!"hours".shouldEqual(4);
    (base - layout.time[4]).total!"hours".shouldEqual(4 * 5);
    (base - layout.time[5]).total!"hours".shouldEqual(4 * 5 + 24);
}

/// This is a blocking operation.
FileLockGuard acquireLock(Path lock) {
    import std.stdio : File;
    import core.thread : getpid;

    auto lockf = File(lock.toString, "w");
    if (!lockf.tryLock)
        throw new SnapshotException(
                SnapshotError(SnapshotException.UnableToAcquireWorkLock(lock.toString)));

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
        remove(fname.toString);
    }
}

void incrSnapshotDirs(Path[] snaps) {
    import std.conv : to;
    import std.file : rename;
    import std.path : baseName, dirName, buildPath, setExtension;
    import std.range : retro;

    if (snaps.length == 0)
        return;

    const dir = snaps[0].dirName;

    foreach (const a; snaps.retro) {
        const oldIdx = a.baseName.to!long;
        const new_ = buildPath(dir.toString, (oldIdx + 1).to!string);
        rename(a.toString, new_);
        rename(a.toString.setExtension(snapshotLog), new_.setExtension(snapshotLog))
            .collectException;
    }
}
