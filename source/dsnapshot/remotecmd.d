/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.remotecmd;

import logger = std.experimental.logger;

import dsnapshot.config;
import dsnapshot.types;

int cmdRemote(const Config.Remotecmd conf) nothrow {
    import std.algorithm : map, filter;
    import std.exception : collectException;
    import std.file : dirEntries, SpanMode, exists, mkdirRecurse, rmdirRecurse;
    import std.path : baseName;
    import std.stdio : writeln;

    final switch (conf.cmd) {
    case RemoteSubCmd.none:
        break;
    case RemoteSubCmd.lsDirs:
        try {
            foreach (p; dirEntries(conf.path, SpanMode.shallow).filter!(a => a.isDir)
                    .map!(a => a.name.baseName)) {
                writeln(p);
            }
        } catch (Exception e) {
        }
        break;
    case RemoteSubCmd.mkdirRecurse:
        try {
            if (!exists(conf.path))
                mkdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    case RemoteSubCmd.rmdirRecurse:
        if (!exists(conf.path))
            return 0;

        try {
            // can fail because a directory is write protected.
            rmdirRecurse(conf.path);
            return 0;
        } catch (Exception e) {
        }

        try {
            foreach (const p; dirEntries(conf.path, SpanMode.depth).filter!(a => a.isDir)) {
                import core.sys.posix.sys.stat;
                import std.file : getAttributes, setAttributes;

                const attrs = getAttributes(p);
                setAttributes(p, attrs | S_IRWXU);
            }
            rmdirRecurse(conf.path);
        } catch (Exception e) {
            logger.warning(e.msg).collectException;
        }
        break;
    }
    return 0;
}

private:
