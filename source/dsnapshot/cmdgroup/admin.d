/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.admin;

import logger = std.experimental.logger;
import std.array : empty, array;
import std.algorithm;
import std.exception : collectException;

import dsnapshot.config : Config;
import dsnapshot.exception;
import dsnapshot.types;

@safe:

int cmdAdmin(Snapshot[] snapshots, const Config.Admin conf) nothrow {
    auto operateOn = () {
        if (conf.names.empty) {
            return snapshots;
        }

        import dsnapshot.set : Set, toSet;

        Set!string pick = conf.names.map!(a => a.value).toSet;
        return snapshots.filter!(a => pick.contains(a.name)).array;
    }();

    foreach (snapshot; operateOn) {
        auto flow = snapshot.syncCmd.match!((None a) => None.init.Flow, (RsyncConfig a) => a.flow);

        try {
            final switch (conf.cmd) with (Config.Admin) {
            case Cmd.list:
                cmdList(snapshot, flow);
            }
        } catch (SnapshotException e) {
            e.errMsg.match!(a => a.print).collectException;
            logger.error(e.msg).collectException;
        } catch (Exception e) {
            logger.error(e.msg).collectException;
            break;
        }
    }

    return 1;
}

private:

void cmdList(Snapshot snapshot, Flow flow) {
    import std.stdio : writeln, stdout;
    import dsnapshot.layout_utils;

    auto layout = snapshot.syncCmd.match!((None a) => snapshot.layout,
            (RsyncConfig a) => fillLayout(snapshot.layout, a.flow, snapshot.remoteCmd));

    writeln("Snapshot config: ", snapshot.name);
    writeln(layout);
}
