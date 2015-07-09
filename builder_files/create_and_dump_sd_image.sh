#!/bin/bash

if [ "$1" == "--tar" ]
then
    MODE=tar
else
    MODE=sd
fi
TMP_DIR=$(mktemp -d)
IMAGE_DIR=$TMP_DIR/img_dir
IMAGE_FILE=$TMP_DIR/img.dd
IMAGE_CONTENT=$TMP_DIR/content

part1()
{
    echo "$(echo -n $1 | sed -e 's/loop/mapper\/loop/')p1"
}

wait_for_device()
{
    while [ ! -e $1 ]
    do
        sleep 0.2
    done
}

# select the files we want in the image
mkdir $IMAGE_CONTENT
cp {zImage,initramfs.cpio.gz,rpi-firmware/*.txt,boot_files/*} \
    $IMAGE_CONTENT >/dev/null

if [ "$MODE" = "tar" ]
then
    cd $IMAGE_CONTENT
    tar cfz - .
else
{
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
    # associate free loop device
    loop_dev=$(losetup -f)
    losetup $loop_dev $IMAGE_FILE

    # let the kernel detect the new partition and create the device
    kpartx -l $loop_dev >&2
    kpartx -a $loop_dev

    # format the partition
    part_dev="$(part1 $loop_dev)"
    wait_for_device $part_dev
    mkfs -t vfat $part_dev

    # mount the partition
    mkdir $IMAGE_DIR
    mount $part_dev $IMAGE_DIR

    # copy files
    cp $IMAGE_CONTENT/* $IMAGE_DIR

    # unmount
    umount $IMAGE_DIR

    # remove the partition mappings
    kpartx -d $loop_dev

    # free loop device
    losetup -d $loop_dev

} >/dev/null

    # dump the image
    gzip --stdout $IMAGE_FILE
fi

# clean up
rm -rf $TMP_DIR

