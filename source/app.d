/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module app;

import logger = std.experimental.logger;
import std;
import colorlog;

int main(string[] args) {
    confLogger(VerboseMode.info);

    auto conf = parseUserArgs(args);

    if (conf.help) {
        conf.printHelp;
        return 0;
    }

    import std.variant : visit;

    // dfmt off
    return conf.data.visit!(
          (Config.Help a) => cmdHelp(conf),
          (Config.Default a) => cmdDefault(a),
    );
    // dfmt on
}

private:

int cmdHelp(Config conf) {
    conf.printHelp;
    return 0;
}

int cmdDefault(Config.Default conf) {
    return 0;
}

struct Config {
    import std.variant : Algebraic;
    static import std.getopt;

    struct Help {
    }

    struct Default {
    }

    alias Type = Algebraic!(Help, Default);

    bool help;
    string progName;
    std.getopt.GetoptResult helpInfo;
    Type data;

    void printHelp() {
        import std.format : format;
        import std.getopt : defaultGetoptPrinter;
        import std.path : baseName;
        import std.string : toLower;

        defaultGetoptPrinter(format("usage: %s <command>\n", progName), helpInfo.options);
        writeln("Command groups:");
        static foreach (T; Type.AllowedTypes) {
            static if (!is(T == Default))
                writeln("  ", T.stringof.toLower);
        }
    }
}

Config parseUserArgs(string[] args) {
    import std.format : format;
    import std.string : toLower;
    static import std.getopt;

    Config conf;
    conf.data = Config.Help.init;
    conf.progName = args[0].baseName;

    string group;
    if (args.length > 1) {
        group = args[1];
        args = args.remove(1);
    }

    try {
        void defaultParse() {
            // dfmt off
            conf.helpInfo = std.getopt.getopt(args,
                );
            // dfmt on
        }

        alias ParseFn = void delegate();
        ParseFn[string] parsers;
        parsers[null] = &defaultParse;
        static foreach (T; Config.Type.AllowedTypes) {
            static if (!is(T == Config.Default) && !is(T == Config.Help))
                mixin(format(`parsers["%1$s"] = &%1$sParse;`, T.stringof.toLower));
        }

        if (auto p = group in parsers) {
            (*p)();
            conf.help = conf.helpInfo.helpWanted;
        } else {
            conf.help = true;
        }
    } catch (std.getopt.GetOptException e) {
        // unknown option
        conf.help = true;
        logger.error(e.msg);
    } catch (Exception e) {
        conf.help = true;
        logger.error(e.msg);
    }

    return conf;
}
