#!/bin/sh
set -e
NFS_MOUNT=/tmp/nfs

on_exit()
{
    echo 'Error! Dropping to a shell.'
    sh
}

prepare()
{
    mount -t proc none /proc
}

mount_nfs()
{
    echo "*** Mounting NFS filesystem ***" 
    eval $(cat /proc/cmdline | tr ' ' "\n" | grep nfs_server)
    eval $(cat /proc/cmdline | tr ' ' "\n" | grep nfs_fs_path)
    echo "NFS server IP : $nfs_server" 
    echo "NFS file system path : $nfs_fs_path"
    mount -o ro,nolock -t nfs $nfs_server:$nfs_fs_path $NFS_MOUNT
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
mount_nfs
mount_union
fix_udev
run_original_init

