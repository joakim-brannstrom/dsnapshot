/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.layout_utils;

import logger = std.experimental.logger;
import std.array : empty;
import std.exception : collectException;

import sumtype;

import dsnapshot.exception;
import dsnapshot.layout : Name, Layout;
import dsnapshot.types;

version (unittest) {
    import unit_threaded.assertions;
}

@safe:

Layout fillLayout(const Layout layout_, const Flow flow, const RemoteCmd cmd) {
    import std.algorithm : filter, map, sort;
    import std.array : array;
    import std.conv : to;
    import std.datetime : UTC, DateTimeException, SysTime;
    import std.file : dirEntries, SpanMode, exists, isDir;
    import std.path : baseName;
    import dsnapshot.layout : LSnapshot = Snapshot;

    Layout rval = layout_.dup;

    const names = flow.match!((None a) => null,
            (FlowRsyncToLocal a) => snapshotNamesFromDir(a.dst.value.Path),
            (FlowLocal a) => snapshotNamesFromDir(a.dst.value.Path),
            (FlowLocalToRsync a) => snapshotNamesFromSsh(cmd, a.dst.addr, a.dst.path));

    foreach (const n; names) {
        try {
            const t = SysTime.fromISOExtString(n.value, UTC());
            rval.put(LSnapshot(t, n));
        } catch (DateTimeException e) {
            logger.warning("Unable to extract the time from the snapshot name");
            logger.info(e.msg);
            logger.info("It is added as a snapshot taken at the time ", SysTime.min);
            rval.put(LSnapshot(SysTime.min, n));
        }
    }

    rval.finalize;

    return rval;
}

Name[] snapshotNamesFromDir(Path dir) @trusted {
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

Name[] snapshotNamesFromSsh(const RemoteCmd cmd_, string addr, string path) {
    import std.algorithm : map, copy;
    import std.array : appender;
    import std.process : execute;
    import std.string : splitLines;

    auto cmd = cmd_.match!((const SshRemoteCmd a) {
        return a.toCmd(RemoteSubCmd.lsDirs, addr, path);
    });
    if (cmd.empty)
        return null;

    auto res = execute(cmd);
    if (res.status != 0) {
        logger.warning(res.output);
        return null;
    }

    auto app = appender!(Name[])();
    res.output.splitLines.map!(a => Name(a)).copy(app);

    return app.data;
}

@("shall scan the directory for all snapshots")
unittest {
    import std.conv : to;
    import std.datetime : SysTime, UTC, Duration, Clock, dur, Interval;
    import std.file;
    import std.path;
    import std.range : enumerate;
    import sumtype;
    import dsnapshot.layout : Layout, LayoutConfig, Span;

    immutable tmpDir = "test_snapshot_scan";
    scope (exit)
        () @trusted { rmdirRecurse(tmpDir); }();
    mkdir(tmpDir);

    const offset = 5.dur!"minutes";
    const base = Clock.currTime.toUTC;
    auto curr = cast() base;

    foreach (const i; 0 .. 15) {
        mkdir(buildPath(tmpDir, curr.toISOExtString));
        curr -= 4.dur!"hours";
    }
    foreach (const i; 0 .. 4) {
        curr -= 8.dur!"hours";
        mkdir(buildPath(tmpDir, curr.toISOExtString));
    }

    auto conf = LayoutConfig([Span(5, 4.dur!"hours"), Span(5, 1.dur!"days")]);
    auto layout = Layout(base, conf);
    layout = fillLayout(layout, FlowLocal(LocalAddr(tmpDir), LocalAddr(tmpDir))
            .Flow, RemoteCmd(SshRemoteCmd.init));

    layout.discarded.length.shouldEqual(10);

    (base - layout.snapshotTimeInBucket(0).get).total!"minutes".shouldEqual(0);
    (base - layout.snapshotTimeInBucket(4).get).total!"hours".shouldEqual(3 * 5 + 1);
    (base - layout.snapshotTimeInBucket(5).get).total!"hours".shouldEqual(4 * 5);
    (base - layout.snapshotTimeInBucket(6).get).total!"hours".shouldEqual(4 * 5 + 24 * 1);
    (base - layout.snapshotTimeInBucket(7).get).total!"hours".shouldEqual(4 * 5 + 24 * 2);
    /// these buckets are filled by the second  pass
    (base - layout.snapshotTimeInBucket(8).get).total!"hours".shouldEqual(4 * 5 + 24 * 3);
    layout.snapshotTimeInBucket(9).isNull.shouldBeTrue;
}
