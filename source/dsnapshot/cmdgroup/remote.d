/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.remote;

import logger = std.experimental.logger;

import dsnapshot.config;
import dsnapshot.types;

int cmdRemote(const Config.Remotecmd conf) nothrow {
    import std.algorithm : map, filter;
    import std.exception : collectException;
    import std.file : dirEntries, SpanMode, exists, mkdirRecurse, rmdirRecurse, rename;
    import std.path : baseName;
    import std.stdio : writeln;

    final switch (conf.cmd) {
    case RemoteSubCmd.none:
        break;
    case RemoteSubCmd.lsDirs:
        try {
            foreach (p; dirEntries(conf.path, SpanMode.shallow).filter!(a => a.isDir)
                    .map!(a => a.name.baseName)) {
                writeln(p);
            }
        } catch (Exception e) {
        }
        break;
    case RemoteSubCmd.mkdirRecurse:
        try {
            if (!exists(conf.path))
                mkdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    case RemoteSubCmd.rmdirRecurse:
        if (!exists(conf.path))
            return 0;

        try {
            // can fail because a directory is write protected.
            rmdirRecurse(conf.path);
            return 0;
        } catch (Exception e) {
        }

        try {
            foreach (const p; dirEntries(conf.path, SpanMode.depth).filter!(a => a.isDir)) {
                import core.sys.posix.sys.stat;
                import std.file : getAttributes, setAttributes;

                const attrs = getAttributes(p);
                setAttributes(p, attrs | S_IRWXU);
            }
            rmdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    case RemoteSubCmd.publishSnapshot:
        if (!exists(conf.path)) {
            logger.infof("Snapshot %s do not exist", conf.path).collectException;
            return 1;
        }

        publishSnapshot(conf.path);
        break;
    case RemoteSubCmd.fakerootStats:
        import std.stdio : File;
        import std.path : buildPath;
        import dsnapshot.stats;

        const fakerootEnv = buildPath(conf.path, snapshotFakerootEnv);
        if (!exists(fakerootEnv)) {
            logger.infof("Unable to find or open %s", conf.path).collectException;
            return 1;
        }
        try {
            auto fkdb = fromFakerootEnv(fakerootEnv.Path);
            writeln; // make sure we start at a new line
            foreach (const ps; fromFakeroot(fkdb, conf.path, buildPath(conf.path, snapshotData)))
                writeln(ps.toString);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
    }
    return 0;
}

/// Publish a snapshot that has the status "in-progress".
int publishSnapshot(const string snapshot) nothrow @safe {
    import std.algorithm : map, filter;
    import std.exception : collectException;
    import std.file : exists, rename, remove, symlink, isSymlink;
    import std.path : dirName, buildPath;
    import std.stdio : writeln;

    const dst = () {
        if (snapshot.length < snapshotInProgressSuffix.length)
            return null;
        return snapshot[0 .. $ - snapshotInProgressSuffix.length];
    }();

    if (exists(dst)) {
        logger.errorf("Destination %s already exist thus unable to publish snapshot %s",
                dst, snapshot).collectException;
        return 1;
    }

    try {
        rename(snapshot, dst);
        const latest = buildPath(dst.dirName, snapshotLatest);
        if (exists(latest) && isSymlink(latest)) {
            remove(latest);
        }
        symlink(dst, latest);
    } catch (Exception e) {
        logger.error(e.msg).collectException;
        return 1;
    }

    return 0;
}
