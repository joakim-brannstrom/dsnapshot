/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module app;

import logger = std.experimental.logger;
import std.algorithm : remove;
import std.path;
import std.stdio : writeln;
import std.string;

import colorlog;

import dsnapshot.backup;
import dsnapshot.config;

int main(string[] args) {
    confLogger(VerboseMode.info);

    auto conf = parseUserArgs(args);

    confLogger(conf.verbosity);

    static foreach (T; Config.Type.AllowedTypes) {
        if (auto a = conf.data.peek!T)
            logger.tracef("%s", *a);
    }

    if (conf.help) {
        return cmdHelp(conf);
    }

    import std.variant : visit;

    // dfmt off
    return conf.data.visit!(
          (Config.Help a) => cmdHelp(conf),
          (Config.Backup a) => cmdBackup(a),
    );
    // dfmt on
}

private:

int cmdHelp(Config conf) {
    conf.printHelp;
    return 0;
}

Config parseUserArgs(string[] args) {
    import std.format : format;
    import std.string : toLower;
    import std.traits : EnumMembers;
    static import std.getopt;

    Config conf;
    conf.data = Config.Help.init;
    conf.progName = args[0].baseName;

    string group;
    if (args.length > 1) {
        group = args[1];
        args = args.remove(1);
    }

    try {
        void backupParse() {
            Config.Backup data;
            scope (success)
                conf.data = data;

            // dfmt off
            string confFile;
            conf.helpInfo = std.getopt.getopt(args,
                "v|verbose", format("Set the verbosity (%-(%s, %))", [EnumMembers!(VerboseMode)]), &conf.verbosity,
                "c|config", "Config file to read", &confFile,
                );
            // dfmt on
            data.confFile = confFile.Path;
        }

        alias ParseFn = void delegate();
        ParseFn[string] parsers;

        static foreach (T; Config.Type.AllowedTypes) {
            static if (!is(T == Config.Help))
                mixin(format(`parsers["%1$s"] = &%1$sParse;`, T.stringof.toLower));
        }

        if (auto p = group in parsers) {
            (*p)();
            conf.help = conf.helpInfo.helpWanted;
        } else {
            conf.help = true;
        }
    } catch (std.getopt.GetOptException e) {
        // unknown option
        conf.help = true;
        logger.error(e.msg);
    } catch (Exception e) {
        conf.help = true;
        logger.error(e.msg);
    }

    return conf;
}

void loadConfig(ref Config conf) @trusted {
    import std.algorithm : filter, map;
    import std.array : array;
    import std.conv : to;
    import std.file : exists, readText;
    import std.path : dirName, buildPath;
    import toml;

    if (conf.data.hasValue && conf.data.convertsTo!(Config.Backup))
        return;

    const confFile = conf.data.get!(Config.Backup).confFile;

    if (!exists(confFile)) {
        logger.errorf("Configuration %s do not exist", confFile);
        return;
    }
}
