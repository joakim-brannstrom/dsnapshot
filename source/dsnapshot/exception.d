/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.exception;

import logger = std.experimental.logger;

import sumtype;

class SnapshotException : Exception {
    this(SnapshotError s) {
        super(null);
        this.errMsg = s;
    }

    SnapshotError errMsg;

    static struct DstIsNotADir {
        void print() {
            logger.error("Destination must be a directory");
        }
    }

    static struct UnableToAcquireWorkLock {
        string dst;
        void print() {
            logger.errorf("'%s' is locked by another dsnapshot instance", dst);
        }
    }

    static struct SyncFailed {
        string src;
        string dst;
        void print() {
            logger.errorf("Failed to sync from '%s' to '%s'", src, dst);
        }
    }

    static struct PreExecFailed {
        void print() {
            logger.error("One or more of the `pre_exec` hooks failed");
        }
    }

    static struct PostExecFailed {
        void print() {
            logger.error("One or more of the `post_exec` hooks failed");
        }
    }
}

alias SnapshotError = SumType!(SnapshotException.DstIsNotADir, SnapshotException.UnableToAcquireWorkLock,
        SnapshotException.SyncFailed, SnapshotException.PreExecFailed,
        SnapshotException.PostExecFailed,);
