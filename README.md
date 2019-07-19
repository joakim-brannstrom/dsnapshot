# dsnapshot

**dsnapshot** is a filesystem snapshot utility based on **rsync**.

dsnapshot makes it easy to keep periodic snapshots of local and remote
machines over ssh.

dsnapshot uses hard links to create an illusion of multiple full backups while
in the background only occupying the space needed for one full plus the
differences. This greatly reduces the disk space required.

Onces dsnapshot is set up your backups can happen automatically, usually
trigged via e.g. a cron job. Because dsnapshot only keeps a fixed number of
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

Note that if the paths are relative they will be relative to where dsnapshot is
executed for a local address.

If the source or destination isn't on the local computer then an address can be
specified in the rsync section:
```toml
src_addr = "foo.com"
# or
dst_addr = "foo.com"
```

## Spans

dsnapshot is aware of how often you want to take snapshots. The span
configuration is what controls how many and with what intervals snapshots are
created and kept on disk.

A basic span is a unique identifier (numerical value), number of snapshots and
the interval.
```
span.<id>.nr = <numerical value>
span.<id>.interval = "<value> <unit>"
```

The supported unites for the interval are `weeks`, `days`, `hours`, `minutes`,
`seoncds` and `msecs`. These can be written in any order, combination and
multiple times.

Multiple spans are concatenated together to a *snapshot layout*. The snapshots
that are taken are automatically mapped into the specified layout as time
progress. Lets say the following configuration:
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

The default span is:
```toml
span.1.nr = 6
span.1.interval = "4 hours"
span.2.nr = 6
span.2.interval = "1 days"
span.2.nr = 3
span.2.interval = "1 weeks"
```

It keeps the backups for up to a month with less and less frequency.

## Advanced config

dsnapshot can run a script before and after a snapshot is created. The snapshot
process will stop if any of the scripts fail.
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

Normally dsnapshot is prohibited from crossing the filesystem. This can be turned off.
```toml
[snapshot.example.rsync]
cross_fs = false
```

Dsnapshot can be configured to exclude directories.
```toml
[snapshot.example.rsync]
exclude = ["path/to/exclude"]
```

The default arguments for rsync can be changed.
```toml
[snapshot.example.rsync]
rsync_args = ["-ahv", "--numeric-ids", "--modify-window", "1"]
```

If the default rsync from the path can't be used. In that case **dsnapshot**
can be configured to use an alternative rsync.
```toml
[snapshot.example.rsync]
rsync_cmd = "path/to/rsync"
```

The command used to calculate the disk usage is by default `du` but can be changed.
```toml
[snapshot.example.rsync]
diskusage_cmd = ["path/to/du", "-hcs"]
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

A progress bar, via rsync, is displayed when dsnapshot is executed in interactive
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

## Example 4: Backup a sql dump

In this example dsnapshot will backup the raw dump of a postgresql database by
executing a script that dumps the database to a file via the `pre_exec` hook.

```toml
[snapshot.example]
span.1.nr = 7
span.1.interval = "1 days"
pre_exec = ["mkdir -p $DSNAPSHOT_SRC", "pg_dumpall -Upostgres > \"$DSNAPSHOT_SRC/dump.sql\""]
post_exec = ["rm \"$DSNAPSHOT_SRC/dump.sql\""]
[snapshot.example.rsync]
src = "~/my_script_dump"
dst = "~/backup/my_script_dump"
```

# Usage

dsnapshot is divided into command groups like git.

## backup

Executes all snapshots in the configuration file.

## verifyconfig

This verify the configuration for errors without executing any commands. Run
with `-v trace` for the most verbose output.

## diskusage

Calculates the actual disk usage of the specified snapshot.

## restore

Restores the snapshot that closest matches the specified date or if none is
given the latest.

# Automation

When you have a configuration file that you are happy with you may want to
automate the execution of the `backup` command.

One way of automating is to use the tried and true crontab. Lets say you have
configured dsnapshots first span to a 4 hours interval and the second is 1 day.
```sh
* */4 * * * dsnapshot backup -c my_config.toml
```

Done! The snapshots will automatically spill over from the 4 hours span to the
1 day span over time.

# Credit

The creator of **rsnapshot** which inspired me to create **dsnapshot**.
