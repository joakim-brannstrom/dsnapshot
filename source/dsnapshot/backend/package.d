/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.datetime : SysTime;

import dsnapshot.backend.crypt;
import dsnapshot.backend.rsync;
import dsnapshot.config;
import dsnapshot.exception;
import dsnapshot.from;
import dsnapshot.process;
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

/**
 */
class CryptException : Exception {
    enum Kind {
        generic,
        wrongPassword,
        errorWhenOpening,
        errorWhenClosing,
        noEncryptedSrc,
    }

    Kind kind;

    this(string msg, Kind kind = Kind.generic, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
        this.kind = kind;
    }
}

/** Encryption of the snapshot destination.
 *
 * One backend only hold at most one target open at a time.
 *
 * Exceptions are used to signal errors.
 *
 * The API excepts this call sequence:
 * One open followed by multiple close.
 * or
 * failed open followed by close.
 */
interface CryptBackend {
    /** Open the encrypted destination.
     *
     * Params:
     * decrypted = where to make the decrypted data visible (mount it).
     */
    void open(const string decrypted);

    /// Close the encrypted destination.
    void close();

    /// If the crypto backend supports hard links and thus --link-dest with e.g. rsync works.
    bool supportHardLinks();

    /// If the crypto backend supports that the encrypted data is on a remote host.
    bool supportRemoteEncryption();
}

// TODO: root and mountPoint is probably not "generic" but until another crypt backend is added this will have to do.
CryptBackend makeCrypBackend(const CryptConfig c) {
    return c.match!((const None a) => cast(CryptBackend) new PlainText,
            (const EncFsConfig a) => new EncFs(a.configFile, a.passwd, a.encryptedPath,
                a.mountCmd, a.mountFuseOpts, a.unmountCmd, a.unmountFuseOpts));
}

/** Open the destination that flow point to.
 *
 * Throws an exception if the destination is not local.
 */
void open(CryptBackend be, const Flow flow) {
    flow.match!((None a) {}, (FlowLocal a) { be.open(a.dst.value); }, (FlowRsyncToLocal a) {
        be.open(a.dst.value);
    }, (FlowLocalToRsync a) {
        if (be.supportRemoteEncryption)
            be.open(null); // TODO for now not implemented
        else
            throw new CryptException("Opening an encryption on a remote host is not supported",
                CryptException.Kind.errorWhenOpening);
    });
}
