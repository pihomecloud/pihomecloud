#!/bin/bash
#{{ansible_managed}}

# By Marc MERLIN <marc_soft@merlins.org>
# License: Apache-2.0
# Modified by pihomecloud https://github.com/pihomecloud/pihomecloud

# Source: http://marc.merlins.org/linux/scripts/
# $Id: btrfs-subvolume-backup 1242 2016-05-31 22:47:09Z svnuser $
#
# Documentation and details at
# http://marc.merlins.org/perso/btrfs/2014-03.html#Btrfs-Tips_-Doing-Fast-Incremental-Backups-With-Btrfs-Send-and-Receive

# cron jobs might not have /sbin in their path.
export PATH="$PATH:/sbin"

set -o nounset
set -o errexit
set -o pipefail

# From https://btrfs.wiki.kernel.org/index.php/Incremental_Backup

# bash shortcut for `basename $0`
PROG=${0##*/}
lock=/tmp/$PROG

usage() {
    cat <<EOF
Usage: 
$PROG	
	[--init] 
	[--keep|-k num]
	[--source hostname] [--port|p 22]
	[--diff]
	[--lockname lockfile (without /var/run prepended)]
	[--postfix foo]
	volume_name /mnt/source_btrfs_pool /mnt/backup_btrfs_pool

Options:
    --help:          Print this help message and exit.
    --init:          For the first run, required to initialize the copy (only use once)
    --lockname|-l:   Override lockfile in /var/run: $PROG
    --keep num:      Keep the last snapshots for local backups (5 by default)
    --dest hostname: If present, ssh to that machine to make the copy.
    --port|-p:       Port number for ssh (defaults to 22).
    --postfix:	     postfix to add to snapshots
    --diff:	     show an approximate diff between the snapshots

This will snapshot volume_name in a btrfs pool, and send the diff
between it and the previous snapshot (volume_name.last) to another btrfs
pool (on other drives)

If your backup destination is another machine, you'll need to add a few
ssh commands this script

The num snapshots to keep is to give snapshots you can recover data from 
and they get deleted after num runs. Set to 0 to disable (one snapshot will
be kept since it's required for the next diff to be computed).
EOF
    exit 0
}

die () {
    msg=${1:-}
    # don't loop on ERR
    trap '' ERR

    rm $lock

    echo "$msg" >&2
    echo >&2

    # This is a fancy shell core dumper
    if echo $msg | grep -q 'Error line .* with status'; then
	line=`echo $msg | sed 's/.*Error line \(.*\) with status.*/\1/'`
	echo " DIE: Code dump:" >&2
	nl -ba $0 | grep -5 "\b$line\b" >&2
    fi
    
    exit 1
}

# Trap errors for logging before we die (so that they can be picked up
# by the log checker)
trap 'die "Error line $LINENO with status $?"' ERR

init=""
# Keep the last 3 snapshots by default
keep=3
TEMP=$(getopt --longoptions help,usage,init,keep:,source:,port:,postfix:,diff,verbose,lockname: -o h,k:,s:,p:,b:,l: -- "$@") || usage
sshSource=localhost
ssh=""
pf=""
diff=""
port=22
verbose=""

# getopt quotes arguments with ' We use eval to get rid of that
eval set -- $TEMP

while :
do
    case "$1" in
        -h|--help|--usage)
            usage
            shift
            ;;

	--postfix)
	    shift
	    pf=_$1
	    lock="$lock.$pf"
	    shift
	    ;;

	--lockname|-l)
	    shift
	    lock="/var/run/$1"
	    shift
	    ;;

	--port|-p)
	    shift
	    port=$1
	    shift
	    ;;

	--keep|-k)
	    shift
	    keep=$1
	    shift
	    ;;

	--source|-s)
	    shift
	    sshSource=$1
	    shift
	    ;;

	--init)
	    init=1
	    shift
	    ;;

	--diff)
	    diff=1
	    shift
	    ;;

	--verbose)
	    verbose=1
	    shift
	    ;;

	--)
	    shift
	    break
	    ;;

        *) 
	    echo "Internal error from getopt!"
	    exit 1
	    ;;
    esac
done
sudo=""
[[ "$(id -u)" != "0" ]] && sudo="sudo"
[[ $keep < 1 ]] && die "Must keep at least one snapshot for things to work ($keep given)"
[[ "$sshSource" != localhost ]] && ssh="ssh -n -p$port $sshSource "
sshNoSudo="$ssh "
ssh="$ssh $sudo "


DATE="$(date '+%Y%m%d_%H:%M:%S')"

[[ $# != 3 ]] && usage
vol="$1"
src_pool="$2"
dest_pool="$3"

lock() {
    local lock_file=$lock

    # create lock file
    eval "exec 42>$lock_file"

    # acquier the lock
    flock -n 42 \
        && return 0 \
        || return 1
}
# shlock (from inn) does the right thing and grabs a lock for a dead process
# (it checks the PID in the lock file and if it's not there, it
# updates the PID with the value given to -p)
if ! lock; then
    echo "$lock held for $PROG, quitting" >&2
    exit
fi

if [[ -z "$init" ]]; then
    [ ! -z "$verbose" ] && echo $ssh /usr/bin/test -e "$dest_pool/${vol}${pf}_last"
    $ssh /usr/bin/test -e "$dest_pool/${vol}${pf}_last" \
	|| die "Cannot sync $src_pool/$vol, $dest_pool/${vol}${pf}_last missing. Try --init?"
    [ ! -z "$verbose" ] && echo $ssh readlink -e $dest_pool/${vol}${pf}_last
    src_snap="$($ssh readlink -e $dest_pool/${vol}${pf}_last)"
fi
src_newsnap="${vol}${pf}_ro.$DATE"
src_newsnaprw="${vol}${pf}_rw.$DATE"

if [ ! -z "$verbose" ]
then
  echo "init=$init"
  [[ -z "$init" ]] && echo "src_snap='$src_snap'"
  echo "src_newsnap='$src_newsnap'"
  echo "src_newsnaprw='$src_newsnaprw'"
fi

test -d "$dest_pool/" || die "ABORT: $dest_pool not a directory (on $sshSource)"

[ ! -z "$verbose" ] && echo "$ssh btrfs subvolume snapshot -r $src_pool/$vol $dest_pool/$src_newsnap"
$ssh btrfs subvolume snapshot -r "$src_pool/$vol" "$dest_pool/$src_newsnap"

if [[ -n "$diff" ]]; then
    echo diff between "$src_snap" "$src_newsnap"
    SNAPSHOT_OLD=$src_snap;
    SNAPSHOT_NEW="$dest_pool/$src_newsnap";
    
    [ ! -z "$verbose" ] && echo "$sshNoSudo test -d $SNAPSHOT_OLD"
    $sshNoSudo test -d $SNAPSHOT_OLD || die "$SNAPSHOT_OLD does not exist";
    [ ! -z "$verbose" ] && echo "$sshNoSudo test -d $SNAPSHOT_NEW"
    $sshNoSudo test -d $SNAPSHOT_NEW || die "$SNAPSHOT_NEW does not exist";
    
    [ ! -z "$verbose" ] && echo "$ssh btrfs subvolume find-new $SNAPSHOT_OLD 99999999999"
    OLD_TRANSID=`$ssh btrfs subvolume find-new "$SNAPSHOT_OLD" 99999999999`
    OLD_TRANSID=${OLD_TRANSID#transid marker was }
    [ -n "$OLD_TRANSID" -a "$OLD_TRANSID" -gt 0 ] || die "Failed to find generation for $SNAPSHOT_NEW"
    
    [ ! -z "$verbose" ] && echo "$ssh btrfs subvolume find-new $SNAPSHOT_NEW $OLD_TRANSID"
    $ssh btrfs subvolume find-new "$SNAPSHOT_NEW" $OLD_TRANSID | sed '$d' | cut -f17- -d' ' | sort | uniq
fi

# There is currently an issue that the snapshots to be used with "btrfs send"
# must be physically on the disk, or you may receive a "stale NFS file handle"
# error. This is accomplished by "sync" after the snapshot
sync

failed=""
if [[ -n "$init" ]]; then
    # Don't throttle speed on initial copy
    [ ! -z "$verbose" ] && echo "$ssh btrfs send '$dest_pool/$src_newsnap' | $sudo btrfs receive -v '$dest_pool/"
    $ssh btrfs send "$dest_pool/$src_newsnap" | $sudo btrfs receive -v "$dest_pool/" || failed=1
else
    [ ! -z "$verbose" ] && echo "$src_snap" "$dest_pool/$src_newsnap"
     # When backing up over ssh, the network should throttle the IO enough, no need to add a 
     # 2nd throttling on disk I/O. This can in extreme cases limit copies to 5GB per hour or so
     # on a local network that supports 50-100GB/h.
     [ ! -z "$verbose" ] && echo "$ssh btrfs send -p '$src_snap' '$dest_pool/$src_newsnap' | $sudo btrfs receive -v '$dest_pool/'"
     $ssh btrfs send -p "$src_snap" "$dest_pool/$src_newsnap" | $sudo btrfs receive -v "$dest_pool/"\
         || failed=1
fi
if [[ -n "$failed" ]]; then
    echo >&2
    echo "ABORT: $ssh btrfs send -p ${src_snap:-} $src_newsnap | $sudo btrfs -v receive $dest_pool/ failed" >&2
    $ssh btrfs subvolume delete "$dest_pool/$src_newsnap" | grep -v 'Transaction commit:'
    $sudo btrfs subvolume delete "$dest_pool/$src_newsnap" | grep -v 'Transaction commit:'
    exit 1
fi

# We make a read-write snapshot in case you want to use it for a chroot
# and some testing with a writeable filesystem or want to boot from a
# last good known snapshot.
#$ssh btrfs subvolume snapshot "$src_newsnap" "$src_newsnaprw"
#$sudo btrfs subvolume snapshot "$dest_pool/$src_newsnap" "$dest_pool/$src_newsnaprw"

# Keep track of the last snapshot to send a diff against.
[ ! -z "$verbose" ] && echo $ssh ln -snf "$dest_pool/$src_newsnap" "$dest_pool/${vol}${pf}_last"
$ssh ln -snf "$dest_pool/$src_newsnap" "$dest_pool/${vol}${pf}_last"
# Keep Track of th e last valid backup
[ ! -z "$verbose" ] && echo $sudo ln -snf "$dest_pool/$src_newsnap" "$dest_pool/${vol}${pf}_last"
$sudo ln -snf "$dest_pool/$src_newsnap" "$dest_pool/${vol}${pf}_last"
# The rw version can be used for mounting with subvol=vol_last_rw
#$ssh ln -snf "$src_newsnaprw" "${vol}${pf}_last_rw"
#ln -snf "$src_newsnaprw" "$dest_pool/${vol}${pf}_last_rw"

# How many snapshots to keep on the source btrfs pool (both read
# only and read-write).
shopt -s nullglob
[ ! -z "$verbose" ] && echo "$ssh ls -rd $dest_pool/${vol}${pf}_ro.*"
[ ! -z "$verbose" ] && $ssh ls -rd "$dest_pool/${vol}${pf}_ro.*" | sort -u | sort -r -t. -k2 | \
        tail -n +$(( $keep + 1 ))
$ssh ls -rd "$dest_pool/${vol}${pf}_ro.*" | sort -u | sort -r -t. -k2 | \
       	tail -n +$(( $keep + 1 ))| while read snap
do
    # Debugging
    [ ! -z "$verbose" ] && echo $ssh btrfs subvolume delete "$snap"
    $ssh btrfs subvolume delete "$snap" | grep -v 'Transaction commit:'
done

#[ ! -z "$verbose" ] && echo "$ssh ls -rd '${vol}${pf}_rw.*'"
#$ssh ls -rd "${vol}${pf}_rw.*" | tail -n +$(( $keep + 1 ))| while read snap
#do
#    [ ! -z "$verbose" ] && echo $ssh btrfs subvolume delete "$snap"
#    $ssh btrfs subvolume delete "$snap" | grep -v 'Transaction commit:'
#done

# Same thing for destination (assume the same number of snapshots to keep,
# you can change this if you really want).

[ ! -z "$verbose" ] && echo "ls -rd $dest_pool/${vol}${pf}_ro*"
[ ! -z "$verbose" ] && ls -rd $dest_pool/${vol}${pf}_ro* | tail -n +$(( $keep + 1 ))
for snap in $(ls -rd $dest_pool/${vol}${pf}_ro* | tail -n +$(( $keep + 1 )))
do
    [ ! -z "$verbose" ] && echo btrfs subvolume delete "$snap"
    $sudo btrfs subvolume delete "$snap" | grep -v 'Transaction commit:'
done
#for snap in $(ls -rd $dest_pool/${vol}${pf}_rw* | tail -n +$(( $keep + 1 )))
#do
#    [ ! -z "$verbose" ] && echo btrfs subvolume delete "$snap"
#    $sudo btrfs subvolume delete "$snap" | grep -v 'Transaction commit:'
#done

rm $lock
echo "[OK] $vol received on $src_newsnap"
echo "[OK] Backup complete"
