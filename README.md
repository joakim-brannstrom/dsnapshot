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

The destination, where the snapshots are stored, can be optionally encrypted.
This is useful when the snapshots are stored in the cloud.

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
`seconds` and `msecs`. These can be written in any order, combination and
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

Dsnapshot can be configured to exclude directories. The path is relative to
src. See `man rsync` for more details.
```toml
[snapshot.example.rsync]
exclude = ["path/to/exclude"]
# which is the actual path: src/path/to/exclude
```

The default arguments for rsync can be changed.
```toml
[snapshot.example.rsync]
rsync_backup_args = ["-ahv", "--numeric-ids", "--modify-window", "1", "--delete", "--delete-excluded", "--partial"]
rsync_restore_args = ["-ahv", "--numeric-ids", "--modify-window", "1"]
```

Lets say that `rsync` from `$PATH` can't be used. In that case dsnapshot can be
configured to use an alternative `rsync`.
```toml
[snapshot.example.rsync]
rsync_cmd = "path/to/rsync"
```

The command used to calculate the disk usage is by default `du` but can be changed.
```toml
[snapshot.example.rsync]
diskusage_cmd = ["path/to/du", "-hcs"]
```

The command used for remote shell execution of snapshots can be configured. It
has overlap with `rsync_rsh`. The difference is that `rsh` is used as is while
`rsync_rsh` configures rsync via `--rsh=<rsync_rsh>`.
```toml
[snapshot.example]
rsh = ["ssh", "-p1234"]
[snapshot.example.rsync]
rsync_rsh = "ssh -p1234"
```

The location of where to find `dsnapshot` on the remote host can be configured.
This is needed when doing a local to remote snapshot:
```toml
[snapshot.example]
dsnapshot = "/path/to/dsnapshot"
```

A progress bar, via rsync, is displayed when dsnapshot is executed in
interactive mode. This can be changed or turned off.
```toml
[snapshot.example.rsync]
progress = ["--info=progress1"]
# or turn off
progress = []
```

The user and group for files can be saved via the excellent `fakeroot` program.
This make it possible to both e.g. backup files owned by root on one host to
another where one do not have root access. By not needing root on the remote
server the security is improved and simplified.
```toml
[snapshot.example.rsync]
fakeroot = true
# additionally the arguments for fakeroot can be changed
fakeroot_args = ["fakeroot", "-u", "-s" "$$SAVE_ENV_FILE$$", "-i", "$$SAVE_ENV_FILE$$"]
# or change to using fakeroot-ng
fakeroot_args = ["fakeroot-ng", "-d", "-p", "$$SAVE_ENV_FILE$$"]
# the rsync command that is executed is the one from rsync_cmd
# this is only used when backing up to another host
rsync_fakeroot_args = ["--rsync-path"]
```

### Configuring encfs for encrypted snapshots

`encfs` can be used to encrypt the snapshots. The configurations parameters for
`encfs` is in the encfs group.

The `encfs` encrypted data (in `encfs` terms the `rootDir`). This must be located
outside of the destination. Both `dst` and `encrypted_path` must exist before
running dsnapshot.
```toml
[snapshot.example.encfs]
encrypted_path = "/foo/bar/encfs"
[snapshot.example.rsync]
dst = "/foo/bar/dst"
```

If the configuration file for the encrypted data is not located in the root of encrypted_path it can be specified.
```toml
[snapshot.example.encfs]
config = "path/to/config.xml"
```

The password for opening the encrypted data can be specified in two ways. The
first one uses `echo` to send the password to `encfs` when it asks for the
password. To avoid printing the password in the logs that dsnapshot produces it
is put in the environment variable `DSNAPSHOT_ENCFS_PWD`. This may be insecure
for your use case so think about it.
```toml
[snapshot.example.encfs]
passwd = "foo"
```

The other way of specifying the password is to replace the arguments that
dsnapshot uses with yours.
```toml
[snapshot.example.encfs]
# to use an external password program you could instead do this
mount_cmd = ["encfs", "-i", "1", "--extpass", "ssh-askpass"]
```

To change what parameters are used when mounting and unmounting. This is useful
when e.g. debugging by add `-v`.
```toml
[snapshot.example.encfs]
mount_cmd = ["encfs", "-i", "1"]
unmount_cmd = ["encfs", "-u"]
```

To pass on extra arguments to FUSE when mounting and unmounting.
```toml
[snapshot.example.encfs]
mount_fuse_opts = ["-o", "myopt"]
unmount_fuse_opts = ["-o", "myopt"]
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

## Example 5: Backup `/` to a remote host

In this example dsnapshot will backup the most relevant files from `/` in order
to ease a restore of the server. To improve the security dsnapshot uses
fakeroot to avoid the need for being root on the remote server when backing up
files owned by root.

The example expects the user `example_backup` to exist on the remote server and
have a ssh key registered that is used by the local root when transferring and
running commands on `dst_addr`.

The example uses the default layout which mean the backups are kept for one
month.

```toml
[snapshot.luggage_root]
dsnapshot = "/home/example_backup/dsnapshot"
rsh = ["ssh", "-l", "example_backup"]
[snapshot.luggage_root.rsync]
exclude = ["dev/", "home/", "media/", "mnt/", "opt/", "proc/", "run/", "sys/",
"tmp/", "var/", "sbin/", "lost+found/", "usr/", "bin/", "lib/", "lib64/",
"snap/", "lib32/", "libx32/"]
src = "/"
dst = "/home/example_backup/root"
dst_addr = "example_backup@lipwig"
fakeroot = true
```

## Example 6: Encrypt the snapshots

In this example the directories used in encrypted_path, src and dst exists
before dsnapshot is executed. encfs has been executed with the arguments
`encfs -f -v ~/backup/example_encfs ~/backup/example` to let it create a
configuration in `~/backup/example_encfs`.

dsnasphot will then open encrypted_path path at dst before doing anything.

The end result is that the snapshots that are taken will be encrypted. This is
useful for storing the snapshots on an untrusted cloud provider.

```toml
[snapshot.example]
[snapshot.example.encfs]
passwd = "my pwd"
encrypted_path = "~/backup/example_encfs"
[snapshot.example.rsync]
src = "~/example"
dst = "~/backup/example"
```

# Usage

dsnapshot is divided into command groups like git.

## backup

Executes all snapshots in the configuration file.

## verifyconfig

This verify the configuration for errors without executing any commands. Run
with `-v trace` for the most verbose output.

## admin

Administrator commands such as calculating the disk usage.

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
