/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.datetime : SysTime;

import dsnapshot.config;
import dsnapshot.exception;
import dsnapshot.from;
import dsnapshot.process;
import dsnapshot.backend.rsync;
public import dsnapshot.backend.crypt;
public import dsnapshot.layout : Layout;
public import dsnapshot.types;

@safe:

/**
 * Error handling is via exceptions.
 */
interface Backend {
    /// Execute a command on the host that is the destination of the snapshots.
    void remoteCmd(const RemoteHost host, const RemoteSubCmd cmd, const string path);

    /// Update layout of the snapshots at the destination.
    Layout update(Layout layout);

    /// Publish the snapshot in dst.
    void publishSnapshot(const string newSnapshot);

    /// Remove discarded snapshots.
    void removeDiscarded(const Layout layout);

    /// Sync from src to dst.
    void sync(const Layout layout, const SnapshotConfig snapshot, const string nameOfNewSnapshot);

    /// Restore dst to src.
    void restore(const Layout layout, const SnapshotConfig snapshot,
            const SysTime time, const string restoreTo);

    /// The flow of data that the backend handles.
    Flow flow();
}

Backend makeSyncBackend(SnapshotConfig s) {
    auto rval = s.syncCmd.match!((None a) { return null; },
            (RsyncConfig a) => new RsyncBackend(a, s.remoteCmd, null));

    if (rval is null) {
        logger.infof("No backend specified for %s. Supported are: rsync", s.name);
        throw new Exception(null);
    }
    return rval;
}

Backend makeSyncBackend(SnapshotConfig s, const dsnapshot.config.Config.Backup backup) {
    auto rval = s.syncCmd.match!((None a) { return null; },
            (RsyncConfig a) => new RsyncBackend(a, s.remoteCmd, backup.ignoreRsyncErrorCodes));

    if (rval is null) {
        logger.infof("No backend specified for %s. Supported are: rsync", s.name);
        throw new Exception(null);
    }
    return rval;
}
