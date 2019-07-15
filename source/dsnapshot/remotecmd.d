/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.remotecmd;

import logger = std.experimental.logger;

import dsnapshot.config;

int cmdRemote(const Config.Remotecmd conf) nothrow {
    import std.algorithm : map, filter;
    import std.exception : collectException;
    import std.file : dirEntries, SpanMode, exists, mkdirRecurse, rmdirRecurse;
    import std.path : baseName;
    import std.stdio : writeln;

    final switch (conf.cmd) with (Config.Remotecmd) {
    case Command.none:
        break;
    case Command.lsDirs:
        try {
            foreach (p; dirEntries(conf.path, SpanMode.shallow).filter!(a => a.isDir)
                    .map!(a => a.name.baseName)) {
                writeln(p);
            }
        } catch (Exception e) {
        }
        break;
    case Command.mkdirRecurse:
        try {
            if (!exists(conf.path))
                mkdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    case Command.rmdirRecurse:
        try {
            if (exists(conf.path))
                rmdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    }
    return 0;
}

private:
