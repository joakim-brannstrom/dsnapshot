/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module config;

public import logger = std.experimental.logger;
public import std;

public import unit_threaded.assertions;

immutable tmpDir = "build/testdata";

string dsnapshotPath() {
    foreach (a; ["../build/dsnapshot"].filter!(a => exists(a)))
        return a.absolutePath;
    assert(0, "unable to find a dsnapshot binary");
}

auto executeDsnapshot(string[] args, string workDir) {
    return execute([dsnapshotPath] ~ args, null, Config.none, size_t.max, workDir);
}

/// Path to where data used for integration tests exists
string testData() {
    return "testdata".absolutePath;
}

auto makeTestArea(string file = __FILE__, int line = __LINE__) {
    return TestArea(file, line);
}

struct TestArea {
    const string workdir;

    this(string file, int line) {
        prepare();
        workdir = buildPath(tmpDir, file.baseName ~ line.to!string).absolutePath;

        if (exists(workdir)) {
            rmdirRecurse(workdir);
        }
        mkdirRecurse(workdir);
    }

    auto execDs(string[] args) {
        return executeDsnapshot(args, workdir);
    }
}

private:

shared(bool) g_isPrepared = false;

void prepare() {
    synchronized {
        if (g_isPrepared)
            return;
        g_isPrepared = true;

        // prepare by cleaning up
        if (exists(tmpDir))
            rmdirRecurse(tmpDir);
    }
}
