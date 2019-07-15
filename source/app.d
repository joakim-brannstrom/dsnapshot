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
import dsnapshot.remotecmd;

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
          (Config.Remotecmd a) => cmdRemote(a),
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

        void globalParse() {
            Config.Backup data;
            scope (success)
                conf.data = data;

            // dfmt off
            conf.global.helpInfo = std.getopt.getopt(args, std.getopt.config.passThrough,
                "v|verbose", format("Set the verbosity (%-(%s, %))", [EnumMembers!(VerboseMode)]), &conf.global.verbosity,
                "c|config", "Config file to read", &confFile,
                );
            // dfmt on
        }

        void backupParse() {
        }

        void remotecmdParse() {
            Config.Remotecmd data;
            scope (success)
                conf.data = data;

            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "cmd", format("Command to execute (%-(%s, %))", [EnumMembers!(Config.Remotecmd.Command)]), &data.cmd,
                "path", "Path argument for the command", &data.path,
                );
            // dfmt on
        }

        alias ParseFn = void delegate();
        ParseFn[string] parsers;

        if (confFile.length != 0)
            conf.global.confFile = confFile.Path;

        globalParse;

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
                    case "rsync":
                        auto rsync = parseRsync(v, name);
                        logger.trace(rsync);
                        s.syncCmd = rsync;
                        break;
                    case "pre_exec":
                        s.hooks.preExec = v.array.map!(a => a.str).array;
                        break;
                    case "post_exec":
                        s.hooks.postExec = v.array.map!(a => a.str).array;
                        break;
                    case "span":
                        auto layout = parseLayout(v);
                        logger.trace(layout);
                        s.layout = layout;
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

import toml : TOMLValue;

auto parseLayout(ref TOMLValue tv) @trusted {
    import std.algorithm : sort, map;
    import std.array : array;
    import std.conv : to;
    import std.datetime : Duration, dur, Clock;
    import std.range : chunks;
    import std.string : split;
    import std.typecons : Nullable;
    import dsnapshot.layout : Span, LayoutConfig, Layout;

    Span[long] spans;

    static Nullable!Span parseASpan(ref TOMLValue data) {
        typeof(return) rval;

        immutable intervalKey = "interval";
        immutable nrKey = "nr";
        if (intervalKey !in data || nrKey !in data) {
            logger.warning("Missing either 'nr' or 'space' key");
            return rval;
        }

        const parts = data[intervalKey].str.split;
        if (parts.length % 2 != 0) {
            logger.warning(
                    "Invalid space specification because either the number or unit is missing");
            return rval;
        }

        Duration d;
        foreach (const p; parts.chunks(2)) {
            const nr = p[0].to!long;
            switch (p[1]) {
            case "minutes":
                d += nr.dur!"minutes";
                break;
            case "hours":
                d += nr.dur!"hours";
                break;
            case "days":
                d += nr.dur!"days";
                break;
            default:
                logger.warningf("Invalid unit '%s'. Valid are minutes, hours and days.", p[1]);
                return rval;
            }
        }

        const nr = data[nrKey].integer;
        if (nr <= 0) {
            logger.warning("nr must be positive");
            return rval;
        }

        rval = Span(cast(uint) nr, d);

        return rval;
    }

    foreach (key, data; tv) {
        logger.tracef("%s %s", key, data);
        try {
            const idx = key.to!long;
            auto span = parseASpan(data);
            if (span.isNull) {
                logger.warning(tv);
            } else {
                spans[idx] = span.get;
            }
        } catch (Exception e) {
            logger.warning(e.msg);
            logger.warning(tv);
        }
    }

    return Layout(Clock.currTime, LayoutConfig(spans.byKeyValue
            .array
            .sort!((a, b) => a.key < b.key)
            .map!(a => a.value)
            .array));
}

auto parseRsync(ref TOMLValue tv, const string parent) @trusted {
    import std.algorithm : map;
    import std.array : array, empty;
    import std.format : format;
    import dsnapshot.types;

    RsyncConfig rval;
    string src, srcAddr, dst, dstAddr;
    foreach (key, data; tv) {
        switch (key) {
        case "src":
            src = data.str;
            break;
        case "src_addr":
            srcAddr = data.str;
            break;
        case "dst":
            dst = data.str;
            break;
        case "dst_addr":
            dstAddr = data.str;
            break;
        case "cmd_rsync":
            rval.cmdRsync = data.str;
            break;
        case "one_fs":
            rval.oneFs = data == true;
            break;
        case "use_fakeroot":
            rval.useFakeRoot = data == true;
            break;
        case "use_link_dest":
            rval.useLinkDest = data == true;
            break;
        case "low_prio":
            rval.lowPrio = data == true;
            break;
        case "exclude":
            rval.exclude = data.array.map!(a => a.str).array;
            break;
        case "rsync_args":
            rval.args = data.array.map!(a => a.str).array;
            break;
        default:
            logger.infof("Unknown option '%s' in section 'snapshot.%s.rsync' in configuration",
                    key, parent);
        }
    }

    if (srcAddr.empty && dstAddr.empty) {
        rval.flow = FlowLocal(LocalAddr(src), LocalAddr(dst));
    } else if (!srcAddr.empty && dstAddr.empty) {
        rval.flow = FlowRsyncToLocal(RsyncAddr(srcAddr, src), LocalAddr(dst));
    } else if (srcAddr.empty && !dstAddr.empty) {
        rval.flow = FlowLocalToRsync(LocalAddr(src), RsyncAddr(dstAddr, dst));
    } else {
        logger.warning("The combination of src, src_addr, dst and dst_addr is not supported. It either has to be local->local, local->remote, remote->local");
    }

    return rval;
}
