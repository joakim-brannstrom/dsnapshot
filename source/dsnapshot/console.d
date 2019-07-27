/**
Copyright: Copyright (c) 2019, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module dsnapshot.console;

@safe:

bool isInteractiveShell() {
    import core.stdc.stdio;
    import core.sys.posix.unistd;

    return isatty(STDERR_FILENO) && isatty(STDOUT_FILENO);
}
