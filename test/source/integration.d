/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module integration;

import config;

@("shall setup a test environment")
unittest {
    makeTestArea;
}

@("shall snapshot local data to dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local.toml"), ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot remote to local dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_remote_to_local.toml"), ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot local to remote dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall keep nr+1 snapshots from a multi-span configuration when executing backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_multiple_spans.toml"), ta.sandboxPath);
    ta.writeDummyData("some data");

    foreach (a; 0 .. 16) {
        import core.thread : Thread;
        import core.time : dur;

        Thread.sleep(10.dur!"msecs");
        ta.execDs("backup").status.shouldEqual(0);
    }

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(14);
    foreach (f; found) {
        f.dirName.dirName.baseName.shouldEqual("dst");
        readText(f).shouldEqual("some data");
    }
}
