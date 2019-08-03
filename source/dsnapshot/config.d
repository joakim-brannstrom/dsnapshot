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
    import std.datetime : SysTime, Duration;
    import std.variant : Algebraic, visit;
    static import std.getopt;

    struct Help {
        std.getopt.GetoptResult helpInfo;
    }

    struct Backup {
        /// The name of the snapshot to backup. If none is specified then all are backed up.
        Name name;
        /// If the user wants to resume an interrupted backup.
        bool resume;
        /// Adjusts the margin used when calculating if a new snapshot should be taken.
        Duration newSnapshotMargin;
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
        std.getopt.GetoptResult helpInfo;
    }

    struct Watch {
        /// The name of the snapshot to backup.
        Name name;
        std.getopt.GetoptResult helpInfo;
    }

    struct Global {
        /// Configuration file to read
        Path confFile;

        VerboseMode verbosity;
        bool help = true;
        string progName;
    }

    alias Type = Algebraic!(Help, Backup, Remotecmd, Restore, Verifyconfig, Admin, Watch);
    Type data;

    Global global;
    SnapshotConfig[] snapshots;

    void printHelp() {
        import std.format : format;
        import std.getopt : defaultGetoptPrinter;
        import std.path : baseName;
        import std.string : toLower;

        static void printGroup(std.getopt.GetoptResult helpInfo, string progName, string name) {
            defaultGetoptPrinter(format("usage: %s %s <options>\n", progName,
                    name), helpInfo.options);
        }

        static void printHelpGroup(std.getopt.GetoptResult helpInfo, string progName) {
            defaultGetoptPrinter(format("usage: %s <command>\n", progName), helpInfo.options);
            writeln("Command groups:");
            static foreach (T; Type.AllowedTypes) {
                writeln("  ", T.stringof.toLower);
            }
        }

        import std.meta : AliasSeq;

        template printers(T...) {
            static if (T.length == 1) {
                static if (is(T[0] == Config.Help))
                    alias printers = (T[0] a) => printHelpGroup(a.helpInfo, global.progName);
                else
                    alias printers = (T[0] a) => printGroup(a.helpInfo,
                            global.progName, T[0].stringof.toLower);
            } else {
                alias printers = AliasSeq!(printers!(T[0]), printers!(T[1 .. $]));
            }
        }

        data.visit!(printers!(Type.AllowedTypes));

        if (data.type == typeid(Verifyconfig)) {
            writeln("Verify the configuration file without actually executing it");
        }
    }
}
