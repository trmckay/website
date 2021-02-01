---
title: "Automated backups with _rsync_, _anacron_, and the cloud"
date: 2020-09-18T16:22:55-07:00
draft: false
---

Everyone knows how devastating it can be to lose all your personal
and configuration files to hardware failure. As such, most users have some way to keep their files
safe. Many choose to use some sort of dotfile management system. This is is a great choice as it
allows for version control and branches for multiple machines. However, dotfiles are not the only
thing you want to preserve. Furthermore, when it comes to backups, more redundancy is never a bad
thing.

When I was looking for a way to keep my files safe, I had a few criteria to find my solution. I
wanted my backups to be:

- **Automatic**: laziness or neglect should not stop my backups from occurring
- **Frequent**: I don't want to be screwed because my PC failed the day before a monthly backup
- **Efficient**: if backups are frequent, I don't want to frequently be dedicating my
  resources to them
- **Distributed**: in other words, keep them in the cloud

I am also the type of person who tends to ignore existing solutions, for worse or for better. Why
spend half an hour reading documentation when I could spend three hours writing a script while
generating content for a blog post at the same time?

# My solution #

Anyway, I went through a few failed attempts and eventually settled on the following solution: `rsync` to do
the synchronization of the target file systems and their destinations, `cronie`/`anacron` to
schedule and automate, and Dropbox for cloud storage (this can still be done with `rclone` and
another cloud service, e.g. Google Drive or Onedrive). Of course, you will need these programs if
you do not have them already.


# Getting familiar with _rsync_ #

Let's first create a script--well, for now it's basically just one command--that can simply
copy one folder to another. We could use `cp`, but lets use `rsync` for _speed_ (among other things).
Here it is:

```bash
#!/bin/bash

SOURCE="$1"
DEST="$2"

echo "Synchronizing $SOURCE to $DEST..."
rsync -a --delete $SOURCE $DEST
```

This is arguably the most important command of the backup script we are
working up to, so let's take a moment to digest it. The `-a` (`--archive`) flag is to preserve
pretty much everything. `--delete` is whats going
to keep your backup from infinitely inflating. I said we were "copying" files earlier, but what
we're really doing is "synchronizing" them. This will make sure if a file is deleted in the
original, it will be later deleted in the backup. Let's not forget the source and target
directories. One lesson I had to learn the hard way, is that `rsync` is very picky about these
arguments. For example `rsync documents backups` will put a copy of `documents` in `backups` so the
resulting directory structure is `backups/documents`. `rsync documents/ backups` does something
slightly different. It copies the _contents_ of `documents` to `backups`. So, if `documents`
contains a folder `school`, the resulting directory structure would be `backups/school`. This is
something to be mindful of as we expand our script.


# Backing up more than one directory #

Wouldn't it be nice if we could back up a bunch of directories at once? I
agree. We can put our sources and destinations in an array like so:

```bash
# sources for backups
declare -a SOURCES
SOURCES[0]="/home"
SOURCES[1]="/etc"
SOURCES[2]="/var/log"

# destinations for backup
declare -a DESTINATIONS
DESTINATIONS[0]="/mnt/hdd1/backups/daily"
DESTINATIONS[1]="/mnt/hdd0/backups/daily"

for CURR_SOURCE in "${SOURCES[@]}"; do
    for CURR_DEST in "${DESTINATIONS[@]}"; do
        rsync -a --quiet --delete $CURR_SOURCE $CURR_DEST/$(dirname $CURR_SOURCE)
    done
done
```

Now, we have a script that will take each source and back it up to each destination. Ideally, your
destinations are all on different drives. That's +1 point in the distributed criterion. Furthermore,
if your destinations are connected via SSH, you can use `rsync` like this:

```bash
rsync -a --quiet --delete --rsh=ssh $CURR_SOURCE $CURR_DEST
```


# Adding some nice features #

This is a good start, but we are still missing some QoL features. Some that came to mind when
writing this were notifications, backup rotation, and checking that destinations exist.

Beginning with device checking, I went for the "low-tech but definitely works" approach. You can
simply declare an array of all the mount locations the script will be writing to and check them:

```bash
# these disks will be checked on run
declare -a DISKS
DISKS[0]="/mnt/hdd0"
DISKS[1]="/mnt/hdd1"

for CURR_DISK in "${DISKS[@]}"; do
    if [ "$(mount | grep $CURR_DISK)" ]; then
        echo "$CURR_DISK found"
    else
        echo "$CURR_DISK not found, aborting"
        exit
    fi
done
```

As for notifications, `notify-send` will work just fine as long as you have a notification server
set up (if you don't know what that is, don't worry, you probably have one). I just have my script
issue a notification when it runs and when it finishes. It can be useful to keep track of that
especially when we start automating it. It is worth noting, however, that running `notify-send` as
root will have some unintended consequences. If you are backing up anything other than your own home
directory, this will certainly affect you. You can use this function to work around that issue
(credit goes to
[Fabio A. on StackOverflow](https://stackoverflow.com/questions/28195805/running-notify-send-as-root)
for that):

```bash
function notify-send() {
    local display=":$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##' | head -n 1)"
    local user=$(who | grep '('$display')' | awk '{print $1}' | head -n 1)
    local uid=$(id -u $user)
    sudo -u $user DISPLAY=$display DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus notify-send "$@"
}
```

One last feature to add is backup rotation. Like I said earlier, redundancy is never bad. So it
can't hurt to keep more if you can spare the disk space. In my case, I opted for one level of
redundancy, but the logic is simple to adapt to more than one level. Essentially, before backing up
the source directory to the target, the target is copied to a `.old` directory.

```bash
for CURR_DEST in "${DESTINATIONS[@]}"; do
    rsync -a --quiet --delete $CURR_DEST/* $CURR_DEST.old
done
```

# Bringing it all together #

Let's take these concepts and make them into a single useful script.

```bash
#!/bin/bash

function notify-send() {
    local display=":$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##' | head -n 1)"
    local user=$(who | grep '('$display')' | awk '{print $1}' | head -n 1)
    local uid=$(id -u $user)
    sudo -u $user DISPLAY=$display DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus notify-send "$@"
}

# sources for backups
declare -a TARGETS
TARGETS[0]="/home"
TARGETS[1]="/etc"
TARGETS[2]="/var/log"

# destinations for backup
# folders will contain ALL targets after backup
declare -a DESTINATIONS
DESTINATIONS[0]="/mnt/hdd1/backups/daily"
DESTINATIONS[1]="/mnt/hdd0/backups/daily"

# these disks will be checked on run
declare -a DISKS
DISKS[0]="/mnt/hdd0"
DISKS[1]="/mnt/hdd1"

echo "Time of backup: $(date)"
notify-send --urgency=critical "Starting backup"

echo "Checking disks..."
for CURR_DISK in "${DISKS[@]}"; do
    if [ -z "$(mount | grep $CURR_DISK)" ]; then
        echo "$CURR_DISK is not mounted, aborting"
        exit
    fi
done

echo "Rotating backups..."
for CURR_DEST in "${DESTINATIONS[@]}"; do
    if [ -d $CURR_DEST ]; then
        rsync -a --quiet --delete $CURR_DEST/* $CURR_DEST.old > /dev/null &
    fi
done
wait

echo "Synchronizing sources to destinations..."
for CURR_SOURCE in "${TARGETS[@]}"; do
    for CURR_DEST in "${DESTINATIONS[@]}"; do
        mkdir -p $CURR_DEST/$CURR_SOURCE
        rsync -a --quiet --delete $CURR_SOURCE $CURR_DEST/$(dirname $CURR_SOURCE) > /dev/null &
    done
done
wait

echo "Backup complete!"
notify-send --urgency=normal "Backup complete"
```

If you look closely, you'll see that the final script makes modifications to most the code we've
written so far. Most of it is just small fixes to make everything work together and background processes to
speed things up. Still, the central idea remains the same: take an array of sources and copy them to
an array of destinations. Make sure to modify the sources and destinations to your liking before
running it. Also, **do not use user specific environment variables**! If you automate this later,
`anacron` will be running your script as root.

Run the script and with any luck you will see something like this:

```
Time of backup: Fri Sep 18 07:12:22 PM PDT 2020
Checking disks...
Rotating backups...
Synchronizing sources to destinations...
Backup complete!
```


# I am lazy (sane) and want to automate this #

This is something, but it would be a lot more convenient if this happened automatically, say, once a
day. Thankfully, this can be done pretty simply with `cronie`/`anacron`. We want to set up a job
that runs this script once a day. We could use `cron` to do this every morning at 10:00 by adding
the following to our crontab:

```cron
0 10 * * * /path/to/backup.sh
```

But, what if you wake up every day at 10:01 for a week, and the script never runs? Tough luck, I
guess--unless you use an asynchronous job. `cronie` comes with this capability built in. Simply
place a link to the script in `/etc/cron.daily` and it will run every day. However, make sure your
link doesn't end it `.sh`. For some reason, `run-parts` (the tool that `cronie` uses to run all the
executables in a directory) doesn't like that. You should also make sure that there is a cron job to
check for asynchronous jobs. You should see something like this in `/etc/crontab`. If not, add it.

```
17 *    * * *   root    cd / && run-parts --report /etc/cron.hourly
25 6    * * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
47 6    * * 7   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
52 6    1 * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
```

And with that, we have fully automated local backups that will run daily, usually within half an hour
of logging in.


# Backing up to the cloud #

Think to yourself: _if my computer were to spontaneously combust, would my backups be safe?_ If the
answer is no, you should probably be backing up to the cloud.

I use Dropbox, and if you do too, doing this is actually pretty simple. Simply copy your backups to
your Dropbox folder every week or so. Of course, we are going to automate this. Thankfully, this is
much simpler than our other script. Here is the script I use to take my daily backup, compress it,
and copy it to my Dropbox.

```bash
#!/bin/bash

WORKING_DIR="/mnt/hdd0/"
SOURCE_DIR="backups/daily"
DESTINATION_FILE="/mnt/hdd0/Dropbox/backups/backup.tar.gz"

cd $WORKING_DIR
tar cf - $SOURCE_DIR | pigz > $DESTINATION_FILE
```

You can set this up as a asynchronous cron job, just like the local backup. Make a link to that
script in `/etc/cron.weekly` and you're good to go.

If you are not using Dropbox, this is a little trickier to do. However, it is possible. `rclone` is
a utility that supports Onedrive, Google Drive, and more. It's syntax is very similar to `rsync`'s.
I'm sure the local backup script provides plenty of inspiration for creating your own script with
`rclone`. Good luck!


# Conclusion #

So, looking back over the checklist we got: automatic ✓, frequent ✓, efficient ✓*, distributed ✓. Some
might argue that spending hours writing a script for a problem that has already been solved is not
efficient. Maybe they have a point. But, you wouldn't be reading random programming blogs if that
approach didn't appeal to you at least a little bit.
