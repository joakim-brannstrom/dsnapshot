/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.config;

import logger = std.experimental.logger;
import std.stdio : writeln;

import colorlog;

public import dsnapshot.types;

struct Config {
    import std.datetime : SysTime;
    import std.variant : Algebraic, visit;
    static import std.getopt;

    struct Help {
    }

    struct Backup {
        /// The name of the snapshot to backup. If none is specified then all are backed up.
        Name name;
        /// If the user wants to resume an interrupted backup.
        bool resume;
        ///
        int[] ignoreRsyncErrorCodes;
        std.getopt.GetoptResult helpInfo;
    }

    struct Remotecmd {
        /// Single path to modify on the remote host.
        string path;
        RemoteSubCmd cmd;
        std.getopt.GetoptResult helpInfo;
    }

    struct Admin {
        /// Name of the snapshot to administrate.
        Name[] names;

        enum Cmd {
            list,
            diskusage,
        }

        Cmd cmd;

        std.getopt.GetoptResult helpInfo;
    }

    struct Restore {
        /// The name of the snapshot to restore.
        Name name;
        /// The time to restore.
        SysTime time;
        /// Path to restore the named snapshot to.
        string restoreTo;
        /// Delete files from restoreTo if they have been removed in src
        bool deleteFromTo;

        std.getopt.GetoptResult helpInfo;
    }

    struct Verifyconfig {
    }

    struct Global {
        /// Configuration file to read
        Path confFile;

        VerboseMode verbosity;
        bool help;
        std.getopt.GetoptResult helpInfo;
        string progName;
    }

    alias Type = Algebraic!(Help, Backup, Remotecmd, Restore, Verifyconfig, Admin);
    Type data;

    Global global;
    Snapshot[] snapshots;

    void printHelp() {
        import std.format : format;
        import std.getopt : defaultGetoptPrinter;
        import std.path : baseName;
        import std.string : toLower;

        defaultGetoptPrinter(format("usage: %s <command>\n", global.progName),
                global.helpInfo.options);
        writeln("Command groups:");
        static foreach (T; Type.AllowedTypes) {
            writeln("  ", T.stringof.toLower);
        }

        data.visit!((Help a) {}, (Backup a) {
            defaultGetoptPrinter("backup:", a.helpInfo.options);
        }, (Remotecmd a) {
            defaultGetoptPrinter("remotecmd:", a.helpInfo.options);
        }, (Restore a) { defaultGetoptPrinter("restore:", a.helpInfo.options); }, (Verifyconfig a) {
            writeln("verifyconfig:");
            writeln("Verify the configuration file without actually executing it");
        }, (Admin a) { defaultGetoptPrinter("admin:", a.helpInfo.options); },);
    }
}
