#!/bin/sh
set -e
NFS_MOUNT=/tmp/nfs

on_exit()
{
    echo 'An error occured.'
    echo 'Rebooting in 5s... (press <Enter> for a shell)'
    read -t 5 && admin_sh || reboot -f
}

admin_sh()
{
    echo 'Starting a shell.'
    echo '(the node will be rebooted on exit.)'
    # see http://www.busybox.net/FAQ.html#job_control
    setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1' || sh
    reboot -f
}

prepare()
{
    mount -t proc none /proc
    mount -t devtmpfs none /dev
}

# we called the DNS in the 1st boot stage and saved the ip
# and hostname as kernel arguments (see kexec.sh).
set_ip()
{   
    eval "$(cat /proc/cmdline | grep -o 'node_ip=[^ ]*')"
    eval "$(cat /proc/cmdline | grep -o 'node_hostname=[^ ]*')"
    # wait for kernel to detect the network interface
    # and enable it
    while [ 1 ]
    do
        ip link set dev eth0 up 2>/dev/null && break || usleep 100000
    done
    # add the ip address
    ip addr add $node_ip dev eth0
    # set the hostname
    hostname $node_hostname
}

mount_nfs()
{
    echo "*** Mounting NFS filesystem ***" 
    eval $(cat /proc/cmdline | tr ' ' "\n" | grep nfs_server)
    eval $(cat /proc/cmdline | tr ' ' "\n" | grep nfs_fs_path)
    echo "NFS server IP : $nfs_server" 
    echo "NFS file system path : $nfs_fs_path"
    # note: nolock is mandatory for use in the minimal
    # system (no portmap)
    mount -o ro,nolock,nocto,noatime,nodiratime -t nfs \
                $nfs_server:$nfs_fs_path $NFS_MOUNT
}

# monitor the nfs mount and reboot the node if nfs connection
# is lost.
# since this background process is run from the initrd, the root
# of its filesystem is in memory, thus it will not be affected
# by the NFS disconnection (unlike all the other processes of the
# image).
# it may seem dirty to keep a background process running after
# the initrd has exec-ed the real OS init, but this is a simple
# and generic way to handle this feature. (Handling it once the
# OS is started instead would involve adding such a mechanism in
# all OS images.)
start_nfs_mount_watchdog()
{
    cd $NFS_MOUNT
    while [ 1 ]
    do
	ls . >/dev/null || reboot -f
	sleep 5
    done &
}

# since we share the NFS export across all rpi nodes,
# this mount must remain read-only.
# in order to enable writes, each rpi will write
# the filesystem changes in memory.
# this is done by using a 'union' filesystem
# called overlayfs.

mount_union()
{
    echo "*** Mounting union ***" 
    # apparently overlayfs now uses extended attributes
    # which are not available on an nfs filesystem
    # so we will work in a tmpfs (memory-based) filesystem,
    # which is able to handle extended attributes.
    mount -t tmpfs tmpfs /tmp/inmemory
    cd /tmp/inmemory

    # creating the union
    # NFS_MOUNT: the nfs mount (that should remain read-only)
    # fs_rw: the place to hold the filesystem changes
    # fs_union: the mount point of the union
    mkdir fs_rw fs_union
    mount -t overlayfs -o upperdir=fs_rw,lowerdir=$NFS_MOUNT union fs_union
}

fix_udev()
{
    # the udev init script expects that /dev is already mounted
    mount -t devtmpfs -o size=10M,mode=0755 -t devtmpfs devtmpfs fs_union/dev
}

run_original_init()
{
    echo "*** Running original init ***" 
    # now we start the orginal init binary
    # rooting the filesystem in fs_union
    cd /tmp/inmemory/fs_union
    exec chroot . sbin/init
}

# let's go
trap on_exit EXIT
prepare
set_ip
mount_nfs
mount_union
fix_udev
start_nfs_mount_watchdog
run_original_init

