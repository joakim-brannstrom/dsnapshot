# dsnapshot

**dsnapshot** is a filesystem snapshot utility based on **rsync**.
**dsnapshot** makes it easy keep periodic snapshots of local and remote
machines over ssh. Rsync and thus by an extension **dsnapshot** make extensive
use of hard links to greatly reduce the disk space required.

Onces **dsnapshot** is set up your backups can happen automatically, usually
trigged via e.g. a cron job. Because **dsnapshot** only keeps a fixed number of
snapshots, as configured, the amount of disk space used will not continue to
grow.

# Getting Started

**dsnapshot** depends on the following software packages:

 * [D compiler](https://dlang.org/download.html) (dmd 2.079+, ldc 1.11.0+)

It is recommended to install the D compiler by downloading it from the official
distribution page.
```sh
curl -fsS https://dlang.org/install.sh | bash -s dmd
```

Once the d compiler is installed you can compile and run dsnapshot.
```sh
git clone https://github.com/joakim-brannstrom/dsnapshot.git
cd dsnapshot
dub build -b release
./build/dsnapshot -h
```

Done! Have fun.
Don't be shy to report any issue that you find.

# Configuration

TODO

# Credit

The creator of **rsnapshot** which inspired me to create **dsnapshot**.
