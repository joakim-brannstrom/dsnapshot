/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.backend.crypt;

import logger = std.experimental.logger;
import std.algorithm : map, filter;
import std.array : empty;
import std.process : Pid;

import sumtype;

import dsnapshot.process;
import dsnapshot.config;
import dsnapshot.exception;
import dsnapshot.layout : Layout;
import dsnapshot.types;

@safe:

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

final class PlainText : CryptBackend {
    override void open(const string decrypted) {
    }

    override void close() {
    }

    override bool supportHardLinks() {
        return true;
    }

    override bool supportRemoteEncryption() {
        return true;
    }
}

/**
 *
 * encfs is started as a daemon with a keepalive timer so it automatically
 * closes when it has been unused for some time. This is because it can take
 * some time both for encfs to open the encrypted data and to finish writing
 * all changes to it.
 *
 * Other designs that has been tried where:
 *
 * # open and close as fast as possible
 * Directly after opening dsnapshot started writing data to the decrypted path
 * and then close it.  If the writing of the data where faster than encfs took
 * to open the encrypted data it would result in everything being lost.
 *
 * # encryp only the snapshot
 * This fails because while we are working on a new snapshot it has the
 * trailing prefix -in-progress.  It is then renamed, by removing the prefix,
 * when it is done. This somehow breaks encfs in mysterious ways.
 */
final class EncFs : CryptBackend {
    import core.sys.posix.sys.stat : stat_t, stat;
    import std.string : toStringz;
    import std.typecons : Nullable;

    Path encrypted;
    Path decrypted;
    string[] mountCmd;
    string[] mountFuseOpts;
    string[] unmountCmd;
    string[] unmountFuseOpts;
    string config;
    string passwd;
    Nullable!stat_t decryptBeforeOpen;

    this(const string config, const string passwd, const string encrypted,
            const string[] mountCmd, const string[] mountFuseOpts,
            const string[] unmountCmd, const string[] unmountFuseOpts) {
        if (encrypted.empty)
            throw new CryptException(null, CryptException.Kind.noEncryptedSrc);

        this.config = config.dup;
        this.passwd = passwd.dup;
        this.encrypted = Path(encrypted);
        this.mountCmd = mountCmd.dup;
        this.mountFuseOpts = mountFuseOpts.dup;
        this.unmountCmd = unmountCmd.dup;
        this.unmountFuseOpts = unmountFuseOpts.dup;
    }

    override void open(const string decrypted) {
        import std.file : exists;

        this.decrypted = decrypted.Path;

        if (isEncryptedOpen) {
            throw new CryptException(null, CryptException.Kind.errorWhenOpening);
        }
        if (!exists(this.encrypted.toString)) {
            throw new CryptException("encrypted path do not exist: " ~ this.encrypted.toString,
                    CryptException.Kind.errorWhenOpening);
        }
        if (!exists(this.decrypted.toString)) {
            throw new CryptException("decrypted path do not exist: " ~ this.decrypted.toString,
                    CryptException.Kind.errorWhenOpening);
        }

        {
            stat_t st = void;
            () @trusted { stat(this.decrypted.toString.toStringz, &st); }();
            decryptBeforeOpen = st;
        }

        string[] cmd = mountCmd;
        if (!config.empty) {
            cmd ~= ["-c", config];
        }
        if (!passwd.empty) {
            // ugly hack
            // hide the password in an environnment variable so it isn't visible in the logs.
            cmd ~= ["--extpass", "echo $DSNAPSHOT_ENCFS_PWD"];
        }

        cmd ~= this.encrypted.toString;
        cmd ~= this.decrypted.toString;

        if (!mountFuseOpts.empty) {
            cmd ~= "--";
            cmd ~= mountFuseOpts;
        }

        try {
            string[string] env = ["DSNAPSHOT_ENCFS_PWD" : passwd];
            spawnProcessLog!(Yes.throwOnFailure)(cmd, env).wait;
        } catch (Exception e) {
            decryptBeforeOpen.nullify;
            logger.warning(e.msg);
            throw new CryptException("encfs failed", CryptException.Kind.errorWhenOpening);
        }
    }

    override void close() @trusted {
        if (!isEncryptedOpen)
            return;

        string[] cmd = unmountCmd;
        cmd ~= decrypted.toString;
        if (!unmountFuseOpts.empty) {
            cmd ~= "--";
            cmd ~= unmountFuseOpts;
        }

        try {
            spawnProcessLog!(Yes.throwOnFailure)(cmd).wait;
            decryptBeforeOpen.nullify;
        } catch (ProcessException e) {
            logger.error(e.msg);
            logger.info("Exit code: ", e.exitCode);
            logger.error("Failed closing the decrypted endpoint ", decrypted.toString);
            throw new CryptException("Unable to close decrypted " ~ this.decrypted.toString,
                    CryptException.Kind.errorWhenClosing);
        }
    }

    override bool supportHardLinks() @safe pure nothrow const @nogc {
        return false;
    }

    override bool supportRemoteEncryption() @safe pure nothrow const @nogc {
        return false;
    }

    private bool isEncryptedOpen() @safe nothrow {
        if (decryptBeforeOpen.isNull)
            return false;

        stat_t st = void;
        () @trusted { stat(decrypted.toString.toStringz, &st); }();

        if (st.st_dev == decryptBeforeOpen.get.st_dev && st.st_ino == decryptBeforeOpen.get.st_ino)
            return false;
        return true;
    }
}
