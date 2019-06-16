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
    import std.variant : Algebraic;
    static import std.getopt;

    struct Help {
    }

    struct Backup {
    }

    struct Global {
        /// Configuration file to read
        Path confFile;

        VerboseMode verbosity;

        bool help;

        std.getopt.GetoptResult helpInfo;

        string progName;
    }

    alias Type = Algebraic!(Help, Backup);
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
    }
}
