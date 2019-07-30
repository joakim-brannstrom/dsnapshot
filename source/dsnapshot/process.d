/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.process;

import logger = std.experimental.logger;
import std.process;
public import std.process : wait;
public import std.typecons : Flag, Yes;

version (unittest) {
    import unit_threaded.assertions;
}

class ProcessException : Exception {
    int exitCode;

    this(int exitCode, string msg = null, string file = __FILE__, int line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
        this.exitCode = exitCode;
    }
}

auto spawnProcessLog(Args...)(const(string)[] cmd_, auto ref Args args) {
    logger.infof("%-(%s %)", cmd_);
    return spawnProcess(cmd_, args);
}

/**
 * Params:
 * throwOnFailure = if true throws a `ProcessException` when the exit code isn't zero.
 */
auto spawnProcessLog(Flag!"throwOnFailure" throw_, Args...)(string[] cmd_, auto ref Args args) {
    logger.infof("%-(%s %)", cmd_);
    auto pid = spawnProcess(cmd_, args);
    return WrapPid!(throw_)(pid);
}

/** Blocks until finished.
 */
auto executeLog(Args...)(const(string)[] cmd_, auto ref Args args) {
    logger.infof("%-(%s %)", cmd_);
    return execute(cmd_, args);
}

struct WrapPid(Flag!"throwOnFailure" throw_) {
    Pid pid;

    auto wait() {
        auto ec = std.process.wait(pid);

        static if (throw_) {
            if (ec != 0)
                throw new ProcessException(ec);
        }

        return ec;
    }
}

@("shall throw a ProcessException when the process fails")
unittest {
    spawnProcessLog!(Yes.throwOnFailure)(["false"]).wait.shouldThrow!(ProcessException);
}
