/**
Copyright: Copyright (c) 2018, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module config;

public import logger = std.experimental.logger;
public import std;

public import unit_threaded.assertions;

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

string inTestData(string p) {
    return buildPath(testData, p);
}

string tmpDir() {
    return "build/test".absolutePath;
}

auto makeTestArea(string file = __FILE__, int line = __LINE__) {
    return TestArea(file, line);
}

struct TestArea {
    const string sandboxPath;
    private int commandLogCnt;

    this(string file, int line) {
        prepare();
        sandboxPath = buildPath(tmpDir, file.baseName ~ line.to!string).absolutePath;

        if (exists(sandboxPath)) {
            rmdirRecurse(sandboxPath);
        }
        mkdirRecurse(sandboxPath);
    }

    auto execDs(Args...)(auto ref Args args_) {
        string[] args;
        static foreach (a; args_)
            args ~= a;
        args ~= ["-v", "trace"];
        auto res = executeDsnapshot(args, sandboxPath);
        try {
            auto fout = File(inSandboxPath(format("command%s.log", commandLogCnt++)), "w");
            fout.writefln("%-(%s %)", args);
            fout.write(res.output);
        } catch (Exception e) {
        }
        return res;
    }

    string[] findFile(string subDir, string basename) {
        string[] files;
        foreach (p; dirEntries(buildPath(sandboxPath, subDir), SpanMode.depth).filter!(
                a => a.baseName == basename))
            files ~= p.name;
        logger.errorf(files.length == 0, "File %s not found in ", basename, subDir);
        return files;
    }

    string inSandboxPath(in string fileName) @safe pure nothrow const {
        import std.path : buildPath;

        return buildPath(sandboxPath, fileName);
    }
}

void writeConfigFromTemplate(Args...)(auto ref TestArea ta, string tmplPath, auto ref Args args) {
    const tmpl = readText(tmplPath);
    File(ta.inSandboxPath(".dsnapshot.toml"), "w").writef(tmpl, args);
}

void writeDummyData(ref TestArea ta, string content) {
    const src = ta.inSandboxPath("src");
    if (!exists(src))
        mkdir(src);
    File(buildPath(src, "file.txt"), "w").write(content);
}

private:

shared(bool) g_isPrepared = false;

void prepare() {
    import core.thread : Thread;
    import core.time : dur;

    synchronized {
        if (g_isPrepared)
            return;
        scope (exit)
            g_isPrepared = true;

        // prepare by cleaning up
        if (exists(tmpDir)) {
            while (true) {
                try {
                    rmdirRecurse(tmpDir);
                    break;
                } catch (Exception e) {
                    logger.info(e.msg);
                }
                Thread.sleep(100.dur!"msecs");
            }
        }
    }
}
