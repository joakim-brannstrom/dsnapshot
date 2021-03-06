/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.types;

public import sumtype;

@safe:

/// Snapshots that are in the progress of being transfered have this suffix.
immutable snapshotInProgressSuffix = "-in-progress";
/// The actual rsync'ed data is in this directory.
immutable snapshotData = "data";
/// name of the fakeroot environment.
immutable snapshotFakerootEnv = "fakeroot.env";
/// User id that is replaced by the actual path to the file to save the env in
immutable snapshotFakerootSaveEnvId = "$$SAVE_ENV_FILE$$";
/// The name of the symlink pointing to the latest snapshot.
immutable snapshotLatest = "latest";

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

    Path opBinary(string op)(string rhs) @safe const {
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

// TODO: maybe rename to SnapshotName?
/// Name of an existing snapshot.
struct Name {
    string value;
}

struct SnapshotConfig {
    import dsnapshot.layout : Layout;

    /// Name of this snapshot
    string name;

    SyncCmd syncCmd;

    // TODO: change to a generic "execute commmand".
    /// How to interact with the destination for e.g. list snapshots.
    RemoteCmd remoteCmd;

    /// The snapshot layout to use.
    Layout layout;

    /// Hooks to run when taking a new snapshot.
    Hooks hooks;

    /// Crypt config.
    CryptConfig crypt;
}

struct Hooks {
    string[] preExec;
    string[] postExec;
}

alias CryptConfig = SumType!(None, EncFsConfig);

struct EncFsConfig {
    /// The xml config for encfs
    string configFile;
    /// Where the encrypted encfs is. The SyncCmd, via Flow, determines where it is mounted.
    string encryptedPath;
    string passwd;
    string[] mountCmd = ["encfs", "-i", "1"];
    string[] mountFuseOpts;
    string[] unmountCmd = ["encfs", "-u"];
    string[] unmountFuseOpts;
}

alias RemoteCmd = SumType!(SshRemoteCmd);

enum RemoteSubCmd {
    none,
    lsDirs,
    mkdirRecurse,
    rmdirRecurse,
    /// Change the status of a snapshot from "in progress" to available.
    publishSnapshot,
    /// Transfer the remote fakeroot.env to a local representation.
    fakerootStats,
}

/// Info of how to execute dsnapshot on the remote host.
struct SshRemoteCmd {
    /// Path/lookup to use to find dsnapshot on the remote host.
    string dsnapshot = "dsnapshot";

    /// dsnapshot is executed via ssh or equivalent command.
    string[] rsh = ["ssh"];

    /// Returns: a cmd to execute with `std.process`.
    string[] toCmd(RemoteSubCmd subCmd, string addr, string path) @safe pure const {
        import std.conv : to;

        return rsh ~ [
            addr, dsnapshot, "remotecmd", "--cmd", subCmd.to!string, "--path",
            path
        ];
    }
}

alias SyncCmd = SumType!(None, RsyncConfig);

struct None {
}

struct LocalAddr {
    string value;

    this(string v) {
        import std.path : expandTilde;

        value = v.expandTilde;
    }
}

struct RemoteHost {
    string addr;
    string path;
}

string fixRemteHostForRsync(const string a) {
    if (a.length != 0 && a[$ - 1] != '/')
        return a ~ "/";
    return a;
}

string makeRsyncAddr(string addr, string path) {
    import std.format : format;

    return format("%s:%s", addr, path);
}

/// Local flow of data.
struct FlowLocal {
    LocalAddr src;
    LocalAddr dst;
}

/// Flow of data using a remote rsync address to a local destination.
struct FlowRsyncToLocal {
    RemoteHost src;
    LocalAddr dst;
}

struct FlowLocalToRsync {
    LocalAddr src;
    RemoteHost dst;
}

alias Flow = SumType!(None, FlowLocal, FlowRsyncToLocal, FlowLocalToRsync);

struct RsyncConfig {
    Flow flow;

    /// If --link-dest should be used with rsync
    bool useLinkDest = true;

    /// One filesystem, don't cross partitions within a backup point.
    bool oneFs = true;

    /// If fakeroot should be used for this snapshot
    bool useFakeRoot = false;

    /// Arguments to use with fakeroot
    string[] rsyncFakerootArgs = ["--rsync-path"];
    string[] fakerootArgs = [
        "fakeroot", "-u", "-i", snapshotFakerootSaveEnvId, "-s",
        snapshotFakerootSaveEnvId
    ];

    /// Low process and io priority
    bool lowPrio = true;

    /// Patterns to exclude from rsync.
    string[] exclude;

    /// Rsync command to use.
    string cmdRsync = "rsync";

    /// disk usage command to use.
    string[] cmdDiskUsage = ["du", "-hcs"];

    /// rsh argument for rsync, --rsh=<rsh>.
    string rsh;

    /// Configure how to print the progress bar when in interactive shell, if any.
    string[] progress = ["--info=stats1", "--info=progress2"];

    // -a archive mode; equals -rlptgoD (no -H,-A,-X)
    // -r recursive
    // -l copy symlinks as symlinks
    // -p preserve permissions
    // -t preserve modification times
    // -g preserve groups permissions
    // -o preserve owner permission
    // -D preserve devices
    // --delete delete files from dest if they are removed in src
    // --partial keep partially transferred files
    // --delete-excluded also delete excluded files from dest dirs
    // --chmod change permission on transfered files
    // --numeric-ids don't map uid/gid values by user/group name
    // --modify-window set the accuracy for mod-time comparisons
    string[] backupArgs = [
        "-ahv", "--numeric-ids", "--modify-window", "1", "--delete",
        "--delete-excluded", "--partial"
    ];

    string[] restoreArgs = ["-ahv", "--numeric-ids", "--modify-window", "1"];
}
