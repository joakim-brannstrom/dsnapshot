/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.process;

import logger = std.experimental.logger;
public import std.process;
public import std.typecons : Flag, Yes;

version (unittest) {
    import unit_threaded.assertions;
}

class ProcessException : Throwable {
    this(int exitCode, string msg = "Process failed") {
        super(msg);
        this.exitCode = exitCode;
    }

    int exitCode;
}

auto spawnProcessLog(Args...)(string[] cmd_, auto ref Args args) {
    logger.infof("%-(%s %)", cmd_);
    return spawnProcess(cmd_, args);
}

/** Blocks until finished.
 *
 * Params:
 * throwOnFailure = if true throws a `ProcessException` when the exit code isn't zero.
 */
auto blockProcess(Flag!"throwOnFailure" throw_, Args...)(string[] cmd_, auto ref Args args) {
    logger.infof("%-(%s %)", cmd_);
    auto pid = spawnProcess(cmd_, args);
    return WrapPid!(throw_)(pid);
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
    blockProcess!(Yes.throwOnFailure)(["false"]).wait.shouldThrow!(ProcessException);
}
