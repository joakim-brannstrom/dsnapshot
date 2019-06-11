/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.config;

import std.stdio : writeln;
public import dsnapshot.types;

struct Config {
    import std.variant : Algebraic;
    static import std.getopt;

    struct Help {
    }

    struct Backup {
        Path confFile;
    }

    alias Type = Algebraic!(Help, Backup);

    bool help;
    string progName;
    std.getopt.GetoptResult helpInfo;
    Type data;

    void printHelp() {
        import std.format : format;
        import std.getopt : defaultGetoptPrinter;
        import std.path : baseName;
        import std.string : toLower;

        defaultGetoptPrinter(format("usage: %s <command>\n", progName), helpInfo.options);
        writeln("Command groups:");
        static foreach (T; Type.AllowedTypes) {
            writeln("  ", T.stringof.toLower);
        }
    }
}
