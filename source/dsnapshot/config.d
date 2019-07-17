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
    import std.variant : Algebraic, visit;
    static import std.getopt;

    struct Help {
    }

    struct Backup {
    }

    struct Remotecmd {
        /// Single path to modify on the remote host.
        string path;
        RemoteSubCmd cmd;
        std.getopt.GetoptResult helpInfo;
    }

    struct Diskusage {
        /// Name of the snapshot to calculate the disk usage of.
        Name name;
        std.getopt.GetoptResult helpInfo;
    }

    struct Global {
        /// Configuration file to read
        Path confFile;

        VerboseMode verbosity;
        bool help;
        std.getopt.GetoptResult helpInfo;
        string progName;
    }

    alias Type = Algebraic!(Help, Backup, Remotecmd, Diskusage);
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

        data.visit!((Help a) {}, (Backup a) {}, (Remotecmd a) {
            defaultGetoptPrinter("remotecmd:", a.helpInfo.options);
        }, (Diskusage a) {
            defaultGetoptPrinter("diskusage:", a.helpInfo.options);
        });
    }
}
