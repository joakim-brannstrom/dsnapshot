# dsnapshot

**dsnapshot** is a filesystem snapshot utility based on **rsync**.

dsnapshot makes it easy keep periodic snapshots of local and remote
machines over ssh.

dsnapshot uses hard links to create an illusion of multiple full backups while
in the background only occupying the space needed for one full plus the
differences. This greatly reduces the disk space required.

Onces dsnapshot is set up your backups can happen automatically, usually
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

**dsnapshot** look by default for the configuration file `.dsnapshot.toml` in
the current directory. The configuration file can be manually specified via
`-c`.

The configuration structure is *named snapshots* with their individual
configuration.

Each snapshot consist of at least one span and src/dst configuration in the
rsync section.
```toml
[snapshot.example]
span.1.nr = 6
span.1.interval = "4 hours"
[snapshot.example.rsync]
src = "path/to/src"
dst = "path/to/where/to/backup/src"
```

If the source or destination isn't on the local computer then an address can be
specified in the rsync section:
```toml
src_addr = "foo.com"
# or
dst_addr = "foo.com"
```

## Spans

The span configuration is what controls how many and with what intervals
snapshots are created.

A basic span is a unique identifier (numerical value), number of snapshots and
the interval.
```
span.<id>.nr = <numerical value>
span.<id>.interval = "<value> <unit>"
```

The supported unites for the interval are `days`, `hours` and `minutes`. These
can be written in any combination and multiple times.

Multiple spans are concatenated together to a total *snapshot layout*. The
snapshots that are taken are automatically mapped into the specified layout as
time progress. Lets say the following configuration:
```toml
span.1.nr = 2
span.1.interval = "12 hours"
span.2.nr = 7
span.2.interval = "7 days"
```

It will result in 9 backups as such:
```
date:    now                                 now-8 days
layout:  __1__2____3____4____5____6____7____8____9
span nr: --1--|--------------2-------------------|
```

There may intermittently exist +1 backup because **dsnapshot** scans the
destination for backups before it creates its new one.

## Advanced config

**dsnapshot** can run a script before and after a snapshot is created.
```toml
[snapshot.example]
pre_exec = ["echo $DSNAPSHOT_SRC $DSNAPSHOT_DST", "echo second script"]
post_exec = ["echo $DSNAPSHOT_SRC $DSNAPSHOT_DST", "echo second script"]
```

Normally the CPU and IO is set to low priority for the rsync process. This can be turned off with:
```toml
[snapshot.example.rsync]
low_prio = false
```

The use of `--link-dest` for rsync can be turned off:
```toml
[snapshot.example.rsync]
link_dest = false
```

Normally rsync is prohibited from crossing the filesystem. This can be turned off.
```toml
[snapshot.example.rsync]
one_fs = false
```

Rsync can be configured to exclude directories.
```toml
[snapshot.example.rsync]
exclude = ["path/to/exclude"]
```

The default arguments for rsync can be changed.
```toml
[snapshot.example.rsync]
rsync_args = ["-ahv", "--partial", "--delete", "--numeric-ids", "--delete-excluded", "--modify-window", "1"]
```

Sometimes the default rsync from the path can't be used. In that case **dsnapshot** can be configured to use an alternative rsync.
```toml
[snapshot.example.rsync]
rsync_cmd = "path/to/rsync"
```

The command use for remote shell execution of snapshots can be configured. It
has  overlap with `rsync_rsh`. The difference is that `rsh` is used as is while
`rsync_rsh` configures rsync via `--rsh=<rsync_rsh>`.
```toml
[snapshot.example]
rsh = ["ssh", "-p1234"]
[snapshot.example.rsync]
rsync_rsh = "ssh -p1234"
```

The location of where to find `dsnapshot` on the remote host can be configured:
```toml
[snapshot.example]
dsnapshot = "/path/to/dsnapshot"
```

A progress bar, via rsync, is display when dsnapshot is executed in interactive
mode. This can be changed or turned off.
```toml
[snapshot.example.rsync]
progress = ["--info=progress1"]
# or turn off
progress = []
```

## Example 1: Backups kept over a year

This will create create a total span of backups that has a higher frequency the
first day (4 hours interval) that will turn into one backup per day for a week.
This is then followed lowered to one per month after that period.

```toml
[snapshot.example]
span.1.nr = 6
span.1.interval = "4 hours"
span.2.nr = 7
span.2.interval = "1 days"
span.3.nr = 4
span.3.interval = "7 days"
span.4.nr = 12
span.4.interval = "30 days"
[snapshot.example.rsync]
src = "~/example"
dst = "~/backup/example"
```

## Exasmple 2: Backup to a remote host

```toml
[snapshot.example]
span.1.nr = 6
span.1.interval = "4 hours"
[snapshot.example.rsync]
src = "~/example"
dst = "~/backup/example"
dst_addr = "other_host"
```

## Example 3: Backup from a remote host

```toml
[snapshot.example]
span.1.nr = 6
span.1.interval = "4 hours"
[snapshot.example.rsync]
src = "~/example"
src_addr = "other_host"
dst = "~/backup/example"
```

# Credit

The creator of **rsnapshot** which inspired me to create **dsnapshot**.
