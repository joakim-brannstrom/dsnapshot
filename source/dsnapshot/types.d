/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.types;

/// Tag a string as a path and make it absolute+normalized.
struct Path {
    import std.path : absolutePath, buildNormalizedPath;

    private string value_;
    alias value this;

    this(Path p) {
        value_ = p.value_;
    }

    this(string p) {
        value_ = p.absolutePath.buildNormalizedPath;
    }

    string value() @safe pure nothrow const @nogc {
        return value_;
    }

    void opAssign(string rhs) @safe pure {
        value_ = rhs.absolutePath.buildNormalizedPath;
    }

    void opAssign(typeof(this) rhs) @safe pure nothrow {
        value_ = rhs.value_;
    }
}

struct Snapshot {
    /// Name of this snapshot
    string name;

    string src;
    string dst;

    string cmdRsync = "/usr/bin/rsync";

    /// If --link-dest should be used with rsync
    bool useLinkDest = true;

    /// One filesystem, don't cross partitions within a backup point.
    bool oneFs = true;

    /// If rsync should be used for this snapshot
    bool useRsync = true;

    /// If fakeroot should be used for this snapshot
    bool useFakeRoot = true;

    /// Low process and io priority
    bool lowPrio = true;

    /// Number of snapshots to keep
    long maxNumber;

    string[] preExec;
    string[] postExec;

    string[] exclude;

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
    string[] rsyncArgs = [
        "-ahv", "--partial", "--delay-updates", "--delete", "--numeric-ids",
        "--relative", "--delete-excluded",
    ];
}
