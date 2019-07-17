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

@("shall snapshot local data to dest when executed")
unittest {
    auto ta = makeTestArea;
    const src = ta.inSandboxPath("src");
    mkdir(src);
    File(buildPath(src, "file.txt"), "w").write("some data");
    copy(buildPath(testData, "test_local.toml"), ta.inSandboxPath(".dsnapshot.toml"));

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot remote to local dest when executed")
unittest {
    auto ta = makeTestArea;
    {
        const tmpl = readText(buildPath(testData, "test_remote_to_local.toml"));
        File(ta.inSandboxPath(".dsnapshot.toml"), "w").writef(tmpl, ta.sandboxPath);

        const src = buildPath(ta.sandboxPath, "src");
        mkdir(src);
        File(buildPath(src, "file.txt"), "w").write("some data");
    }

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot local to remote dest when executed")
unittest {
    auto ta = makeTestArea;
    {
        const tmpl = readText(buildPath(testData, "test_local_to_remote.toml"));
        File(buildPath(ta.sandboxPath, ".dsnapshot.toml"), "w").writef(tmpl,
                dsnapshotPath, buildPath(ta.sandboxPath));

        const src = buildPath(ta.sandboxPath, "src");
        mkdir(src);
        File(buildPath(src, "file.txt"), "w").write("some data");
    }

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}
