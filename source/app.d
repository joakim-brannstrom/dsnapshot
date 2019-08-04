/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module app;

import logger = std.experimental.logger;
import std.algorithm : remove, map, filter;
import std.array : array, empty;
import std.exception : collectException;
import std.path : baseName, expandTilde;
import std.stdio : writeln;

import colorlog;

import dsnapshot.config;

int main(string[] args) {
    import dsnapshot.cmdgroup.admin;
    import dsnapshot.cmdgroup.backup;
    import dsnapshot.cmdgroup.remote;
    import dsnapshot.cmdgroup.restore;
    import dsnapshot.cmdgroup.watch;

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

    // dfmt off
    return conf.data.visit!(
      (Config.Help a) => cmdHelp(conf),
      (Config.Backup a) {
          loadConfig(conf);
          return cmdBackup(conf.global, a, conf.snapshots);
      },
      (Config.Remotecmd a) => cmdRemote(a),
      (Config.Restore a) {
          loadConfig(conf);
          return cmdRestore(conf.snapshots, a);
      },
      (Config.Verifyconfig a) {
          loadConfig(conf);
          logger.info("Done");
          return 0;
      },
      (Config.Admin a) {
          loadConfig(conf);
          return cmdAdmin(conf.snapshots, a);
      },
      (Config.Watch a) {
          loadConfig(conf);
          return cli(conf.global, a, conf.snapshots);
      }
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
        void globalParse() {
            Config.Help data;
            scope (success)
                conf.data = data;

            string confFile;
            // dfmt off
            data.helpInfo = std.getopt.getopt(args, std.getopt.config.passThrough,
                "v|verbose", format("Set the verbosity (%-(%s, %))", [EnumMembers!(VerboseMode)]), &conf.global.verbosity,
                "c|config", "Config file to read", &confFile,
                );
            // dfmt on
            conf.global.help = data.helpInfo.helpWanted;
            args ~= (conf.global.help ? "-h" : null);

            if (!confFile.empty)
                conf.global.confFile = confFile.Path;
        }

        void backupParse() {
            Config.Backup data;
            scope (success)
                conf.data = data;

            string margin;
            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "force", "Force a backup to be taken even though it isn't time for it", &data.forceBackup,
                "ignore-rsync-error-code", "Ignore rsync error code", &data.ignoreRsyncErrorCodes,
                "margin", "Add a margin when checking if a new snapshot should be taken", &margin,
                "resume", "If an interrupted backup should be resumed", &data.resume,
                "s|snapshot", "The name of the snapshot to backup (default: all)", &data.name.value,
                );
            // dfmt on
            data.newSnapshotMargin = parseDuration(margin);
        }

        void remotecmdParse() {
            Config.Remotecmd data;
            scope (success)
                conf.data = data;

            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "cmd", format("Command to execute (%-(%s, %))", [EnumMembers!(RemoteSubCmd)]), &data.cmd,
                "path", "Path argument for the command", &data.path,
                );
            // dfmt on
        }

        void restoreParse() {
            import std.datetime : SysTime, UTC, Clock;

            Config.Restore data;
            scope (success)
                conf.data = data;

            string time;
            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "delete", "Delete files from dst if they are removed in the snapshot", &data.deleteFromTo,
                "dst", "Where to restore the snapshot", &data.restoreTo,
                "s|snapshot", "Name of the snapshot to calculate the disk usage for", &data.name.value,
                "time", "Pick the snapshot that is closest to this time (default: now). Add a trailing Z if UTC", &time,
                );
            // dfmt on

            try {
                if (time.length == 0)
                    data.time = Clock.currTime;
                else
                    data.time = SysTime.fromISOExtString(time);
            } catch (Exception e) {
                logger.error(e.msg);
                throw new Exception("Example of UTC time: 2019-07-18T10:49:29.5765454Z");
            }
        }

        void verifyconfigParse() {
            conf.data = Config.Verifyconfig.init;
        }

        void adminParse() {
            Config.Admin data;
            scope (success)
                conf.data = data;

            string[] names;
            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "s|snapshot", "Snapshot name (default: all)", &names,
                "cmd", format!"What to do. Available: %-(%s, %) (default: list)"([EnumMembers!(Config.Admin.Cmd)]), &data.cmd,
                );
            // dfmt on

            data.names = names.map!(a => Name(a)).array;
        }

        void watchParse() {
            Config.Watch data;
            scope (success)
                conf.data = data;

            // dfmt off
            data.helpInfo = std.getopt.getopt(args,
                "max-nr", "Exit after this number of snapshots has been created", &data.maxSnapshots,
                std.getopt.config.required, "s|snapshot", "The name of the snapshot to backup", &data.name.value,
                );
            // dfmt on
        }

        alias ParseFn = void delegate();
        ParseFn[string] parsers;

        static foreach (T; Config.Type.AllowedTypes) {
            static if (!is(T == Config.Help))
                mixin(format(`parsers["%1$s"] = &%1$sParse;`, T.stringof.toLower));
        }

        globalParse;

        if (auto p = group in parsers) {
            (*p)();
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
    import std.conv : to;
    import std.file : exists, readText, isFile;
    import std.path : dirName, buildPath;
    import toml;

    scope (exit)
        logger.trace(conf);

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
            SnapshotConfig s;
            s.name = name;
            s.layout = makeDefaultLayout;
            foreach (k, v; data) {
                try {
                    switch (k) {
                    case "rsync":
                        auto rsync = parseRsync(v, name);
                        s.syncCmd = rsync;
                        break;
                    case "encfs":
                        s.crypt = parseEncfs(v, name);
                        break;
                    case "pre_exec":
                        s.hooks.preExec = v.array.map!(a => a.str).array;
                        break;
                    case "post_exec":
                        s.hooks.postExec = v.array.map!(a => a.str).array;
                        break;
                    case "span":
                        auto layout = parseLayout(v);
                        s.layout = layout;
                        break;
                    case "dsnapshot":
                        s.remoteCmd = s.remoteCmd.match!((SshRemoteCmd a) {
                            a.dsnapshot = v.str;
                            return a;
                        });
                        break;
                    case "rsh":
                        s.remoteCmd = s.remoteCmd.match!((SshRemoteCmd a) {
                            a.rsh = v.array.map!(a => a.str).array;
                            return a;
                        });
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
    import std.algorithm : sort;
    import std.conv : to;
    import std.datetime : Clock;
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

        auto d = parseDuration(data[intervalKey].str);

        const nr = data[nrKey].integer;
        if (nr <= 0) {
            logger.warning("nr must be positive");
            return rval;
        }

        rval = Span(cast(uint) nr, d);

        return rval;
    }

    foreach (key, data; tv) {
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
        case "cross_fs":
            rval.oneFs = data == true;
            break;
        case "fakeroot":
            rval.useFakeRoot = data == true;
            break;
        case "rsync_fakeroot_args":
            rval.rsyncFakerootArgs = data.array.map!(a => a.str).array;
            break;
        case "fakeroot_args":
            rval.fakerootArgs = data.array.map!(a => a.str).array;
            break;
        case "link_dest":
            rval.useLinkDest = data == true;
            break;
        case "low_prio":
            rval.lowPrio = data == true;
            break;
        case "exclude":
            rval.exclude = data.array.map!(a => a.str).array;
            break;
        case "rsync_cmd":
            rval.cmdRsync = data.str;
            break;
        case "rsync_rsh":
            rval.rsh = data.str;
            break;
        case "diskusage_cmd":
            rval.cmdDiskUsage = data.array.map!(a => a.str).array;
            break;
        case "rsync_backup_args":
            rval.backupArgs = data.array.map!(a => a.str).array;
            break;
        case "rsync_restore_args":
            rval.restoreArgs = data.array.map!(a => a.str).array;
            break;
        case "progress":
            rval.progress = data.array.map!(a => a.str).array;
            break;
        default:
            logger.infof("Unknown option '%s' in section 'snapshot.%s.rsync' in configuration",
                    key, parent);
        }
    }

    if (srcAddr.empty && dstAddr.empty) {
        rval.flow = FlowLocal(LocalAddr(src.expandTilde), LocalAddr(dst));
    } else if (!srcAddr.empty && dstAddr.empty) {
        rval.flow = FlowRsyncToLocal(RemoteHost(srcAddr, src), LocalAddr(dst));
    } else if (srcAddr.empty && !dstAddr.empty) {
        rval.flow = FlowLocalToRsync(LocalAddr(src), RemoteHost(dstAddr, dst));
    } else {
        logger.warning("The combination of src, src_addr, dst and dst_addr is not supported. It either has to be local->local, local->remote or remote->local");
    }

    return rval;
}

auto parseEncfs(ref TOMLValue tv, const string parent) @trusted {
    import std.format : format;
    import dsnapshot.types;

    EncFsConfig rval;

    foreach (key, data; tv) {
        switch (key) {
        case "config":
            rval.configFile = data.str;
            break;
        case "encrypted_path":
            rval.encryptedPath = data.str;
            break;
        case "passwd":
            rval.passwd = data.str;
            break;
        case "mount_cmd":
            rval.mountCmd = data.array.map!(a => a.str).array;
            break;
        case "mount_fuse_opts":
            rval.mountFuseOpts = data.array.map!(a => a.str).array;
            break;
        case "unmount_cmd":
            rval.unmountCmd = data.array.map!(a => a.str).array;
            break;
        case "unmount_fuse_opts":
            rval.unmountFuseOpts = data.array.map!(a => a.str).array;
            break;
        default:
            logger.infof("Unknown option '%s' in section 'snapshot.%s.encfs' in configuration",
                    key, parent);
        }
    }

    if (rval.encryptedPath.empty) {
        logger.error("No 'encrypted_path' specified for ", parent);
    }

    return rval;
}

/** The default layout to use if none is specified by the user.
 */
auto makeDefaultLayout() {
    import std.datetime : Clock, dur;
    import dsnapshot.layout;

    const base = Clock.currTime;
    auto conf = LayoutConfig([
            Span(6, 4.dur!"hours"), Span(6, 1.dur!"days"), Span(3, 1.dur!"weeks")
            ]);
    return Layout(base, conf);
}

auto parseDuration(string timeSpec) {
    import std.conv : to;
    import std.string : split;
    import std.datetime : Duration, dur;
    import std.range : chunks;

    Duration d;
    const parts = timeSpec.split;

    if (parts.length % 2 != 0) {
        logger.warning("Invalid time specification because either the number or unit is missing");
        return d;
    }

    foreach (const p; parts.chunks(2)) {
        const nr = p[0].to!long;
        bool validUnit;
        immutable AllUnites = [
            "msecs", "seconds", "minutes", "hours", "days", "weeks"
        ];
        static foreach (Unit; AllUnites) {
            if (p[1] == Unit) {
                d += nr.dur!Unit;
                validUnit = true;
            }
        }
        if (!validUnit) {
            logger.warningf("Invalid unit '%s'. Valid are %-(%s, %).", p[1], AllUnites);
            return d;
        }
    }

    return d;
}
