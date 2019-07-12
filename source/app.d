/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module app;

import logger = std.experimental.logger;
import std.algorithm : remove;
import std.exception : collectException;
import std.path;
import std.stdio : writeln;
import std.string;

import colorlog;

import dsnapshot.backup;
import dsnapshot.config;

int main(string[] args) {
    confLogger(VerboseMode.info);

    auto conf = parseUserArgs(args);

    confLogger(conf.global.verbosity);

    logger.trace(conf.global);
    static foreach (T; Config.Type.AllowedTypes) {
        if (auto a = conf.data.peek!T)
            logger.tracef("%s", *a);
    }

    if (conf.global.help) {
        return cmdHelp(conf);
    }

    import std.variant : visit;

    loadConfig(conf);
    logger.trace(conf);

    // dfmt off
    return conf.data.visit!(
          (Config.Help a) => cmdHelp(conf),
          (Config.Backup a) => cmdBackup(conf.global, a, conf.snapshots),
    );
    // dfmt on
}

@safe:
private:

int cmdHelp(Config conf) @trusted {
    conf.printHelp;
    return 0;
}

Config parseUserArgs(string[] args) @trusted {
    import std.format : format;
    import std.string : toLower;
    import std.traits : EnumMembers;
    static import std.getopt;

    Config conf;
    conf.data = Config.Help.init;
    conf.global.progName = args[0].baseName;
    conf.global.confFile = ".dsnapshot.toml";

    string group;
    if (args.length > 1) {
        group = args[1];
        args = args.remove(1);
    }

    try {
        string confFile;

        void backupParse() {
            Config.Backup data;
            scope (success)
                conf.data = data;

            // dfmt off
            conf.global.helpInfo = std.getopt.getopt(args,
                "v|verbose", format("Set the verbosity (%-(%s, %))", [EnumMembers!(VerboseMode)]), &conf.global.verbosity,
                "c|config", "Config file to read", &confFile,
                );
            // dfmt on
        }

        alias ParseFn = void delegate();
        ParseFn[string] parsers;

        if (confFile.length != 0)
            conf.global.confFile = confFile.Path;

        static foreach (T; Config.Type.AllowedTypes) {
            static if (!is(T == Config.Help))
                mixin(format(`parsers["%1$s"] = &%1$sParse;`, T.stringof.toLower));
        }

        if (auto p = group in parsers) {
            (*p)();
            conf.global.help = conf.global.helpInfo.helpWanted;
        } else {
            conf.global.help = true;
        }
    } catch (std.getopt.GetOptException e) {
        // unknown option
        conf.global.help = true;
        logger.error(e.msg);
    } catch (Exception e) {
        conf.global.help = true;
        logger.error(e.msg);
    }

    return conf;
}

void loadConfig(ref Config conf) @trusted {
    import std.algorithm : filter, map;
    import std.array : array;
    import std.conv : to;
    import std.file : exists, readText, isFile;
    import std.path : dirName, buildPath;
    import toml;

    if (!exists(conf.global.confFile.toString) || !conf.global.confFile.toString.isFile) {
        logger.errorf("Configuration %s do not exist", conf.global.confFile);
        return;
    }

    static auto tryLoading(string configFile) {
        auto txt = readText(configFile);
        auto doc = parseTOML(txt);
        return doc;
    }

    TOMLDocument doc;
    try {
        doc = tryLoading(conf.global.confFile.toString);
    } catch (Exception e) {
        logger.warning("Unable to read the configuration from ", conf.global.confFile);
        logger.warning(e.msg);
        return;
    }

    alias Fn = void delegate(ref Config c, ref TOMLValue v);
    Fn[string] tables;

    tables["snapshot"] = (ref Config c, ref TOMLValue snapshots) {
        foreach (name, data; snapshots) {
            Snapshot s;
            s.name = name;
            foreach (k, v; data) {
                try {
                    switch (k) {
                    case "src":
                        s.src = v.str;
                        break;
                    case "dst":
                        s.dst = v.str;
                        break;
                    case "cmd_rsync":
                        s.cmdRsync = v.str;
                        break;
                    case "one_fs":
                        s.oneFs = v == true;
                        break;
                    case "use_fakeroot":
                        s.useFakeRoot = v == true;
                        break;
                    case "use_link_dest":
                        s.useLinkDest = v == true;
                        break;
                    case "use_rsync":
                        s.useRsync = v == true;
                        break;
                    case "low_prio":
                        s.lowPrio = v == true;
                        break;
                    case "exclude":
                        s.exclude = v.array.map!(a => a.str).array;
                        break;
                    case "pre_exec":
                        s.preExec = v.array.map!(a => a.str).array;
                        break;
                    case "post_exec":
                        s.postExec = v.array.map!(a => a.str).array;
                        break;
                    case "rsync_args":
                        s.rsyncArgs = v.array.map!(a => a.str).array;
                        break;
                    case "nr":
                        s.maxNumber = v.integer;
                        break;
                    default:
                        logger.infof("Unknown option '%s' in section 'snapshot.%s' in configuration",
                                k, name);
                    }
                } catch (Exception e) {
                    logger.error(e.msg).collectException;
                }
            }
            c.snapshots ~= s;
        }
    };

    tables["main"] = (ref Config c, ref TOMLValue table) {
        foreach (k, v; table) {
            try {
                switch (k) {
                default:
                    logger.infof("Unknown option '%s' in section 'main' in configuration", k);
                }
            } catch (Exception e) {
                logger.error(e.msg).collectException;
            }
        }
    };

    foreach (curr; doc.byKeyValue.filter!(a => a.value.type == TOML_TYPE.TABLE)) {
        try {
            if (auto t = curr.key in tables) {
                (*t)(conf, curr.value);
            } else {
                logger.infof("Unknown section '%s' in configuration", curr.key);
            }
        } catch (Exception e) {
            logger.error(e.msg).collectException;
        }
    }
}
