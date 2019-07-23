/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.stats;

import logger = std.experimental.logger;

import dsnapshot.types : Path;

version (unittest) {
    import unit_threaded.assertions;
}

/// Stats for a dev+inode as it is in a fakeroot environment.
struct FakerootStat {
    static struct Node {
        // ID of device containing file
        ulong dev;
        // Inode number
        ulong inode;

        size_t toHash() @safe pure nothrow const @nogc scope {
            auto a = dev.hashOf();
            return inode.hashOf(a); // mixing two hash values
        }

        bool opEquals()(auto ref const S s) const {
            return s.dev == dev && s.inode == inode;
        }
    }

    Node node;
    alias node this;

    // File type and mode
    ulong mode;
    // User ID of owner
    ulong uid;
    // Group ID of owner
    ulong gid;
    // Device ID (if special file)
    ulong rdev;

    import std.range : isOutputRange;

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put;

        put(w, typeof(this).stringof);
        put(w, "(");
        formattedWrite(w, "dev=%s", node.dev);
        formattedWrite(w, ",inode=%s", node.inode);
        formattedWrite(w, ",hash=%s", node.toHash);
        formattedWrite(w, ",mode=%s", mode);
        formattedWrite(w, ",uid=%s", uid);
        formattedWrite(w, ",gid=%s", gid);
        formattedWrite(w, ",rdev=%s", rdev);
        put(w, ")");
    }
}

/** Parse a fakeroot configuration line.
 *
 * Example:
 * dev=37,ino=15312816,mode=100664,uid=1000,gid=1000,rdev=0
 */
FakerootStat fromFakeroot(const(char)[] s) {
    import std.format : formattedRead;

    typeof(return) rval;
    ulong nlink;
    s.formattedRead!"dev=%x,ino=%d,mode=%o,uid=%d,gid=%d,nlink=%d,rdev=%d"(rval.dev,
            rval.inode, rval.mode, rval.uid, rval.gid, nlink, rval.rdev);
    return rval;
}

@("shall convert a fakeroot line to FakerootStat")
unittest {
    auto res = fromFakeroot("dev=37,ino=15312816,mode=100664,uid=1000,gid=1000,nlink=1,rdev=0");
    res.dev.shouldEqual(55);
    res.inode.shouldEqual(15312816);
    res.mode.shouldEqual(33204);
    res.uid.shouldEqual(1000);
    res.gid.shouldEqual(1000);
    res.rdev.shouldEqual(0);
}

struct FakerootDb {
    import std.typecons : Nullable;

    alias Set = FakerootStat[FakerootStat.Node];
    Set db;

    void put(FakerootStat v) {
        db[v.node] = v;
    }

    Nullable!FakerootStat get(FakerootStat.Node node) {
        typeof(return) rval;
        if (auto v = node in db) {
            rval = *v;
        }
        return rval;
    }

    import std.range : isOutputRange;

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        put(w, typeof(this).stringof);
        put(w, "(");

        foreach (const a; db.byValue) {
            a.toString(w);
            put(w, ",");
        }

        put(w, ")");
    }
}

/// Stats for a path.
struct PathStat {
    /// Path relative to the destination.
    string path;

    /// File type and mode
    ulong mode;
    /// User ID of owner
    ulong uid;
    /// Group ID of owner
    ulong gid;
    /// Device ID (if special file)
    ulong rdev;

    import std.range : isOutputRange;

    string toString() @safe pure const {
        import std.array : appender;

        auto buf = appender!string;
        toString(buf);
        return buf.data;
    }

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.format : formattedWrite;
        import std.range : put;

        formattedWrite(w, "mode=%o", mode);
        formattedWrite(w, ",uid=%s", uid);
        formattedWrite(w, ",gid=%s", gid);
        formattedWrite(w, ",rdev=%s", rdev);
        formattedWrite(w, ",path=%s", path);
    }
}

@("shall convert PathStat to a string")
unittest {
    import std.conv : octal;

    PathStat("foo/bar", octal!100664, 1000, 1001, 0).toString.shouldEqual(
            "mode=100664,uid=1000,gid=1001,rdev=0,path=foo/bar");
}

PathStat fromPathStat(const(char)[] s) {
    import std.format : formattedRead;

    typeof(return) rval;
    s.formattedRead!"mode=%o,uid=%d,gid=%d,rdev=%d,path=%s"(rval.mode,
            rval.uid, rval.gid, rval.rdev, rval.path);
    return rval;
}

@("shall convert from string to pathstat")
unittest {
    import std.conv : octal;

    auto p = fromPathStat("mode=100664,uid=1000,gid=1001,rdev=0,path=foo/bar");
    p.shouldEqual(PathStat("foo/bar", octal!100664, 1000, 1001, 0));
}

PathStat[] fromFakeroot(ref FakerootDb db, const string root, const string relRoot) {
    import std.algorithm : filter;
    import std.array : array;
    import std.file : dirEntries, SpanMode;
    import std.path : relativePath;

    PathStat[string] rval;

    foreach (f; dirEntries(root, SpanMode.depth).filter!(a => a.name !in rval)) {
        const st = f.statBuf;
        auto stdb = db.get(FakerootStat.Node(st.st_dev, st.st_ino));
        if (!stdb.isNull)
            rval[f.name] = PathStat(relativePath(f.name, relRoot),
                    stdb.get.mode, stdb.get.uid, stdb.get.gid, stdb.get.rdev);
    }

    return rval.byValue.array;
}

FakerootDb fromFakerootEnv(const Path p) {
    import std.stdio : File;

    FakerootDb fkdb;
    foreach (const l; File(p.toString).byLine)
        fkdb.put(fromFakeroot(l));
    return fkdb;
}
