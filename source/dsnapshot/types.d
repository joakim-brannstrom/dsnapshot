/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.types;

public import sumtype;

/// Tag a string as a path and make it absolute+normalized.
struct Path {
    import std.path : absolutePath, buildNormalizedPath, buildPath;

    private string value_;

    this(Path p) @safe pure nothrow @nogc {
        value_ = p.value_;
    }

    this(string p) @safe {
        value_ = p.absolutePath.buildNormalizedPath;
    }

    Path dirName() @safe const {
        import std.path : dirName;

        return Path(value_.dirName);
    }

    string baseName() @safe const {
        import std.path : baseName;

        return value_.baseName;
    }

    void opAssign(string rhs) @safe pure {
        value_ = rhs.absolutePath.buildNormalizedPath;
    }

    void opAssign(typeof(this) rhs) @safe pure nothrow {
        value_ = rhs.value_;
    }

    Path opBinary(string op)(string rhs) @safe {
        static if (op == "~") {
            return Path(buildPath(value_, rhs));
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    void opOpAssign(string op)(string rhs) @safe nothrow {
        static if (op == "~=") {
            value_ = buildNormalizedPath(value_, rhs);
        } else
            static assert(false, typeof(this).stringof ~ " does not have operator " ~ op);
    }

    T opCast(T : string)() {
        return value_;
    }

    string toString() @safe pure nothrow const @nogc {
        return value_;
    }

    import std.range : isOutputRange;

    void toString(Writer)(ref Writer w) const if (isOutputRange!(Writer, char)) {
        import std.range : put;

        put(w, value_);
    }
}

//TODO: rename to SnapshotConfig
struct Snapshot {
    import dsnapshot.layout : Layout;

    /// Name of this snapshot
    string name;

    SumType!(None, RsyncConfig) syncCmd;

    /// The snapshot layout to use.
    Layout layout;

    string[] preExec;
    string[] postExec;
}

struct None {
}

struct LocalAddr {
    string value;
}

struct RsyncAddr {
    string value;

    this(string a) {
        if (a.length != 0 && a[$ - 1] != '/')
            value = a ~ "/";
        else
            value = a;
    }
}

/// Local flow of data.
struct FlowLocal {
    LocalAddr src;
    LocalAddr dst;
}

/// Flow of data using a remote rsync address to a local destination.
struct FlowRsyncToLocal {
    RsyncAddr src;
    LocalAddr dst;
}

alias Flow = SumType!(None, FlowLocal, FlowRsyncToLocal);

struct RsyncConfig {
    Flow flow;

    /// If --link-dest should be used with rsync
    bool useLinkDest = true;

    /// One filesystem, don't cross partitions within a backup point.
    bool oneFs = true;

    /// If fakeroot should be used for this snapshot
    bool useFakeRoot = true;

    /// Low process and io priority
    bool lowPrio = true;

    /// Patterns to exclude from rsync.
    string[] exclude;

    /// Rsync command to use
    string cmdRsync;

    // -a archive mode; equals -rlptgoD (no -H,-A,-X)
    // -r recursive
    // -l copy symlinks as symlinks
    // -p preserve permissions
    // -t preserve modification times
    // -g preserve groups permissions
    // -o preserve owner permission
    // -D preserve devices
    // --delay-updates save files in a destination directory and then do a atomic update
    // --delete delete files from dest if they are removed in src
    // --chmod change permission on transfered files
    // --partial keep partially transferred files
    // --numeric-ids don't map uid/gid values by user/group name
    // --relative use relative path names
    // --delete-excluded also delete excluded files from dest dirs
    string[] args = [
        "-ahv", "--partial", "--delay-updates", "--delete", "--numeric-ids",
        "--relative", "--delete-excluded",
    ];
}
