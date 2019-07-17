/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.cmdgroup.diskusage;

import logger = std.experimental.logger;
import std.algorithm;
import std.exception : collectException;

import dsnapshot.config;
import dsnapshot.types;

int cmdDiskUsage(const Snapshot[] snapshots, const Config.Diskusage conf) nothrow {
    foreach (const snapshot; snapshots.filter!(a => a.name == conf.name.value)) {
        try {

        } catch (Exception e) {
            logger.error(e.msg).collectException;
            break;
        }

        return 0;
    }

    logger.errorf("No snapshot with the name %s found", conf.name.value).collectException;
    return 1;
}
