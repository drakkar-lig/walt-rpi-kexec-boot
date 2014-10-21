#!/bin/bash

IMAGE_PARTITION_DEVICE="/dev/mapper/loop0p1"
TMP_DIR=$(mktemp -d)
IMAGE_DIR=$TMP_DIR/img_dir
IMAGE_FILE=$TMP_DIR/img.dd
IMAGE_CONTENT=$TMP_DIR/content
mkdir $IMAGE_DIR $IMAGE_CONTENT

{
    # select the files we want in the image
    cp {zImage,initramfs.cpio.gz,rpi-firmware/*.txt,boot_files/*} $IMAGE_CONTENT

    # we want to create a small image.
    # let's estimate the needed image size with 'du' and multiply it by 4/3.
    needed_size_megabytes=$(set -- $(du -sm $IMAGE_CONTENT); echo $((4*$1/3)))

    # ensure it is at least 8M (otherwise fdisk will not be happy)
    needed_size_megabytes=$((needed_size_megabytes>8?needed_size_megabytes:8))

    # create the image file
    # Note: creating a file with hole (i.e. using dd's seek option) is faster,
    # but we prefer to ensure uninitialized data is 0, for better compression of
    # the resulting image.
    dd if=/dev/zero of=$IMAGE_FILE count=$needed_size_megabytes bs=1M 2>/dev/null

    # create partition
    fdisk $IMAGE_FILE 2>/dev/null << EOF
n
p
1


t
b
w
EOF

    # let the kernel detect the new partition and create the device
    kpartx -a $IMAGE_FILE

    # format the partition
    mkfs -t vfat $IMAGE_PARTITION_DEVICE

    # mount the partition
    mount $IMAGE_PARTITION_DEVICE $IMAGE_DIR

    # copy files
    cp $IMAGE_CONTENT/* $IMAGE_DIR

    # unmount
    umount $IMAGE_DIR

    # remove the partition mappings
    kpartx -d $IMAGE_FILE

} >/dev/null

# dump the image
gzip --stdout $IMAGE_FILE

# clean up
rm -rf $TMP_DIR

