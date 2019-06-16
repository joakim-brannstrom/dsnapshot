/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backup;

import logger = std.experimental.logger;

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
}

private:

SnapshotStatus snapshot(const Snapshot snapshot) {
    import std.algorithm : startsWith, filter, map, sort;
    import std.array : array;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : dirName, baseName;
    import std.process : execute, executeShell, spawnProcess, spawnShell;

    Path[] snapDirs = scanForSnapshots(snapshot.dst);

    return SnapshotStatus.ok;
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
