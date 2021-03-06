/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module integration;

import core.thread : Thread;
import core.time : dur;

import config;

@("shall setup a test environment")
unittest {
    makeTestArea;
}

@("shall snapshot local data to dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local.toml"));
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(2);
    found[0].dirName.baseName.shouldEqual("data");
    found[0].dirName.dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot remote to local dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_remote_to_local.toml"), ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(2);
    found[0].dirName.baseName.shouldEqual("data");
    found[0].dirName.dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall snapshot local to remote dest when executed backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);
    ta.execDs("backup", "--force").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(3);
    found[0].dirName.baseName.shouldEqual("data");
    found[0].dirName.dirName.dirName.baseName.shouldEqual("dst");
    readText(found[0]).shouldEqual("some data");
}

@("shall keep only those snapshots that are best fit for the buckets from a multi-span configuration when executing backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_multiple_spans.toml"), ta.sandboxPath);
    ta.writeDummyData("some data");

    foreach (a; 0 .. 10) {
        Thread.sleep(20.dur!"msecs");
        ta.execDs("backup").status.shouldEqual(0);
    }
    Thread.sleep(200.dur!"msecs");
    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    // the first bucket is left empty because the sleep above ensure that we
    // run the command backup so many times that the snapshots just gets old
    // and fall out.
    found.length.shouldBeGreaterThan(1);
    foreach (f; found) {
        f.dirName.baseName.shouldEqual("data");
        f.dirName.dirName.dirName.baseName.shouldEqual("dst");
        readText(f).shouldEqual("some data");
    }
}

@("shall calculate the disk usage of a local destination when executing diskusage")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local.toml"), ta.sandboxPath);
    ta.writeDummyData("0123456789");

    ta.execDs("backup").status.shouldEqual(0);
    auto res = ta.execDs("admin", "--cmd", "diskusage", "-s", "a");

    res.status.shouldEqual(0);
    ta.sandboxPath.shouldBeIn(res.output);
    "total".shouldBeIn(res.output);
}

@("shall calculate the disk usage of a remote destination when executing diskusage")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("0123456789");

    ta.execDs("backup").status.shouldEqual(0);
    auto res = ta.execDs("admin", "--cmd", "diskusage", "-s", "a");

    res.status.shouldEqual(0);
    ta.sandboxPath.shouldBeIn(res.output);
    "total".shouldBeIn(res.output);
}

@("shall verify the configuration when executing verifyconfig")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote.toml"),
            dsnapshotPath, ta.sandboxPath);

    auto res = ta.execDs("verifyconfig");

    res.status.shouldEqual(0);
    "Done".shouldBeIn(res.output);
}

@("shall restore the latest local snapshot to destination when executing restore")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local.toml"), ta.sandboxPath);

    ta.writeDummyData("0123456789");
    ta.execDs("backup").status.shouldEqual(0);
    Thread.sleep(10.dur!"msecs");
    ta.writeDummyData("9876543210");
    ta.execDs("backup").status.shouldEqual(0);
    ta.execDs("restore", "-s", "a", "--dst", ta.inSandboxPath("restore")).status.shouldEqual(0);

    const found = ta.findFile("restore", "file.txt");
    found.length.shouldEqual(1);
    found[0].dirName.baseName.shouldNotEqual("data");
    // the one closest to the configured snapshot time is "best". The time is
    // now-5min so the first snapshot should be restored.
    readText(found[0]).shouldEqual("0123456789");
}

@("shall restore the latest remote snapshot to destination when executing restore")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote.toml"),
            dsnapshotPath, ta.sandboxPath);

    ta.writeDummyData("0123456789");
    ta.execDs("backup").status.shouldEqual(0);
    Thread.sleep(10.dur!"msecs");
    ta.writeDummyData("9876543210");
    ta.execDs("backup").status.shouldEqual(0);
    ta.execDs("restore", "-s", "a", "--dst", ta.inSandboxPath("restore")).status.shouldEqual(0);

    const found = ta.findFile("restore", "file.txt");
    found.length.shouldEqual(1);
    // the one closest to the configured snapshot time is "best". The time is
    // now-5min so the first snapshot should be restored.
    readText(found[0]).shouldEqual("0123456789");
}

@("shall save the env via fakeroot for a local to local when executing backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_fakeroot.toml"), ta.sandboxPath);
    ta.writeDummyData("0123456789");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "fakeroot.env");
    found.length.shouldEqual(2);
}

@("shall save the env via fakeroot for a local to remote when executing backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote_fakeroot.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("0123456789");

    ta.execDs("backup").status.shouldEqual(0);

    const found = ta.findFile("dst", "fakeroot.env");
    found.length.shouldEqual(2);
}

@("shall restore from a local snapshot using the fakeroot env when executing restore")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_fakeroot.toml"), ta.sandboxPath);
    ta.writeDummyData("0123456789");

    {
        ta.execDs("backup").status.shouldEqual(0);
        const found = ta.findFile("dst", "fakeroot.env");
        const fenv = readText(found[0]);
        File(found[0], "w").write(fenv.replace("mode=100664", "mode=100600"));
    }

    ta.execDs("restore", "-s", "a", "--dst", ta.inSandboxPath("restore")).status.shouldEqual(0);

    {
        const found = ta.findFile("restore", "file.txt");
        found.length.shouldEqual(1);
        found[0].getAttributes.shouldEqual(octal!100600);
    }
}

@("shall restore from a remote snapshot using the fakeroot env when executing restore")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote_fakeroot.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("0123456789");

    {
        ta.execDs("backup").status.shouldEqual(0);
        const found = ta.findFile("dst", "fakeroot.env");
        const fenv = readText(found[0]);
        File(found[0], "w").write(fenv.replace("mode=100664", "mode=100600"));
    }

    ta.execDs("restore", "-s", "a", "--dst", ta.inSandboxPath("restore")).status.shouldEqual(0);

    {
        const found = ta.findFile("restore", "file.txt");
        found.length.shouldEqual(1);
        found[0].getAttributes.shouldEqual(octal!100600);
    }
}

@("shall sync to a crypto backend")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_encfs.toml"),
            inTestData("test_local_encfs.xml"), ta.inSandboxPath("encfs"));
    ta.writeDummyData("some data");
    mkdirRecurse(ta.inSandboxPath("encfs"));
    mkdirRecurse(ta.inSandboxPath("dst"));

    ta.execDs("backup").status.shouldEqual(0);

    // should be closed
    dirEntries(ta.inSandboxPath("dst"), SpanMode.depth).count.shouldEqual(0);
    // three files because it should be the snapshot with a date, the
    dirEntries(ta.inSandboxPath("encfs"), SpanMode.depth).count.shouldEqual(4);

    // opening to inspect the content
    spawnProcess([
            "encfs", "-i", "1", "-c", inTestData("test_local_encfs.xml"),
            "--extpass", "echo smurf", ta.inSandboxPath("encfs"),
            ta.inSandboxPath("dst")
            ]).wait;
    scope (exit)
        execute(["encfs", "-u", ta.inSandboxPath("dst")]);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(2);
    readText(found[0]).shouldEqual("some data");
}

@("shall create a snapshot when backup is called with --force and the timer hasnt elapsed yet")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local.toml"));
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);
    // not created
    ta.execDs("backup").status.shouldEqual(0);
    // but now
    ta.execDs("backup", "--force").status.shouldEqual(0);

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(3);
}

@("shall create a snapshot when the files in src changes")
unittest {
    import std.concurrency : spawn, send, receiveTimeout, receiveOnly, ownerTid;

    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_watch.toml"));
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);

    static void modifyFile(string fname) {
        bool running = true;
        int i = 0;
        while (running) {
            receiveTimeout(10.dur!"msecs", (bool a) { running = false; });
            File(fname, "w").write("dummy");
        }
        send(ownerTid, true);
    }

    auto modifyTid = spawn(&modifyFile, ta.inSandboxPath("src/file.txt"));
    ta.execDs("watch", "-s", "a", "--max-nr", "5").status.shouldEqual(0);
    send(modifyTid, true);
    receiveOnly!bool;

    const found = ta.findFile("dst", "file.txt");
    found.length.shouldEqual(7);
    readText(found[0]).shouldEqual("some data");
    readText(found[4]).shouldEqual("dummy");
}

@("shall execute the pre and post hooks when creating a snapshot via backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_hooks.toml"), dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);
    ta.execDs("backup", "--force").status.shouldEqual(0);

    ta.findFile("src", "dsnapshot_src_pre").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_dst_pre").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_data_dst_pre").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_latest_pre").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_data_latest_pre").length.shouldEqual(1);

    ta.findFile("src", "dsnapshot_src_post").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_dst_post").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_data_dst_post").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_latest_post").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_data_latest_post").length.shouldEqual(1);
}

@("shall execute the pre and post hooks when creating a snapshot via backup")
unittest {
    auto ta = makeTestArea;
    ta.writeConfigFromTemplate(inTestData("test_local_to_remote_hooks.toml"),
            dsnapshotPath, ta.sandboxPath);
    ta.writeDummyData("some data");

    ta.execDs("backup").status.shouldEqual(0);
    ta.execDs("backup", "--force").status.shouldEqual(0);

    ta.findFile("src", "dsnapshot_src_pre").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_dst_pre").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_data_dst_pre").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_latest_pre").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_data_latest_pre").length.shouldEqual(1);

    ta.findFile("src", "dsnapshot_src_post").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_dst_post").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_data_dst_post").length.shouldEqual(3);
    ta.findFile("dst", "dsnapshot_latest_post").length.shouldEqual(1);
    ta.findFile("dst", "dsnapshot_data_latest_post").length.shouldEqual(1);
}
