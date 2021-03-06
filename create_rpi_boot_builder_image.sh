#!/bin/bash
eval "$(docker run waltplatform/dev-master env)"
THIS_DIR=$(cd $(dirname $0); pwd)
TMP_DIR=$(mktemp -d)
LOC_BUILDROOT=/tmp/buildroot
LOC_INITRD=/tmp/initrd
BUILD_PACKAGES="git subversion make gcc g++ libncurses5-dev bzip2 wget cpio python unzip bc kpartx dosfstools"
SVN_RPI_FIRMWARE_BOOT_FILES="https://github.com/raspberrypi/firmware/trunk/boot"
INITRD2_BUSYBOX_APPLETS="cat chroot grep mkdir mount sh tr ls reboot sleep setsid ip usleep hostname timeout"

cd "$THIS_DIR"
cp -rp   builder_files/* $TMP_DIR

cd $TMP_DIR

cat > Dockerfile << EOF
FROM $DOCKER_DEBIAN_BASE_IMAGE
MAINTAINER $DOCKER_IMAGE_MAINTAINER

RUN apt-get update && apt-get install -y $BUILD_PACKAGES

# Buidroot
# --------
# This will prepare a minimal system that will be booted 
# on the raspberry pi.

RUN git clone git://git.buildroot.net/buildroot $LOC_BUILDROOT
WORKDIR $LOC_BUILDROOT
RUN git checkout $RPI_BOOT_BUIDROOT_GIT_TAG
RUN sed -i "s/KEXEC_VERSION =.*/KEXEC_VERSION = $RPI_BOOT_KEXEC_VERSION/g" package/kexec/kexec.mk

# buildroot config
ADD buildroot_rpi_defconfig $LOC_BUILDROOT/configs/

# busybox config
RUN sed -i -e 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' package/busybox/busybox.config
RUN sed -i -e 's/.*CONFIG_TIMEOUT.*/CONFIG_TIMEOUT=y/' package/busybox/busybox.config
RUN sed -i -e 's/.*CONFIG_NC.*/CONFIG_NC=y/' package/busybox/busybox.config

# generate buildroot .config with unspecified options to their defaults
RUN make buildroot_rpi_defconfig

# linux kernel config
ADD walt_bcmrpi_linux.config $LOC_BUILDROOT/walt_bcmrpi_linux.config

# run.
# the build directory will be eating much disk space at the end
# so we will remove it in order to keep the docker container smaller.
# however we must save the busybox binary because we will need it below.
RUN make && \
    cp output/build/busybox*/busybox output/busybox && \
    rm -rf output/build

# initrd of 2nd kernel
# --------------------
# This will prepare a tiny filesystem archive. 
# When the 2nd step linux kernel is loaded using kexec,
# it will be booted in this filesystem. 
# the bin/init script contained there is responsible for
# mounting the filesystem union that will prevent writes on
# the NFS-mounted final filesystem of the node.

RUN mkdir -p $LOC_INITRD/initrd_fs
WORKDIR $LOC_INITRD/initrd_fs
ADD boot2/init.sh $LOC_INITRD/initrd_fs/init
ADD boot2/prepare.sh $LOC_INITRD/initrd_fs/prepare.sh
RUN chmod +x ./init ./prepare.sh
RUN mkdir -p bin proc tmp/inmemory tmp/nfs
WORKDIR $LOC_INITRD/initrd_fs/bin
RUN cp $LOC_BUILDROOT/output/busybox .
RUN for cmd in $INITRD2_BUSYBOX_APPLETS; do ln -s busybox \$cmd; done
WORKDIR $LOC_INITRD/initrd_fs
RUN find . | cpio -H newc -o | gzip > ../initrd.cpio.gz

# initrd of 1st kernel
# --------------------
# This will modify the buildroot-generated filesystem archive.
# This filesystem is the one that is first loaded when the raspberry pi
# boots its 1st kernel, the one stored on the sd-card.
# It is responsible for retrieving the 2nd kernel from the NFS server,
# boot it using kexec inside the initrd built on the previous step (see above).

RUN mkdir $LOC_BUILDROOT/output/images/rootfs
WORKDIR $LOC_BUILDROOT/output/images/rootfs
RUN tar xf ../rootfs.tar
ADD boot1/init $LOC_BUILDROOT/output/images/rootfs/
ADD boot1/boot.sh boot1/prepare.sh $LOC_BUILDROOT/output/images/rootfs/root/
RUN chmod +x init root/*.sh
RUN cp $LOC_INITRD/initrd.cpio.gz root/
# Disable login prompt
RUN sed -i "s/^tty/#tty/g" etc/inittab
# Run boot1/boot.sh script on boot
RUN echo "::once:/root/boot.sh" >> etc/inittab
RUN find . | cpio -H newc -o | gzip > ../initramfs.cpio.gz
WORKDIR $LOC_BUILDROOT/output/images
RUN rm -rf rootfs*

# rpi firmware files setup
# ------------------------
RUN echo "console=ttyAMA0,115200 console=tty1 ip=none panic=5" > rpi-firmware/cmdline.txt
RUN echo "disable_splash=1" >> rpi-firmware/config.txt
RUN echo "initramfs initramfs.cpio.gz" >> rpi-firmware/config.txt
# the repository is big because it's made of (versioned!) binary files.
# although it's on github, we use svn instead of git, because it allows us to download only a 
# subdirectory of it.
# (also, we don't need some of the files, we can remove them)
RUN svn checkout $SVN_RPI_FIRMWARE_BOOT_FILES ./boot_files && \
    rm -f ./boot_files/kernel*.img ./boot_files/start_*.elf ./boot_files/fixup_*.dat

# install entry point
# -------------------
ADD create_and_dump_sd_image.sh /entry_point.sh
ENTRYPOINT ["/entry_point.sh"]
CMD []

EOF
docker build -t "$DOCKER_RPI_BOOT_BUILDER_IMAGE" .
result=$?

echo "TODO: improve all this."
echo "- install a cross compiler through package management and use it in buildroot instead of compiling it"
echo "- check if we cannot use a package manager -installed static busybox and build the 2 initrds manually (we would need kexec and portmap also...)"
echo "- if we could use the same kernel as in the rpi-debian image, we could adapt boot1/boot.sh for the case where the 2nd kernel is the same and boot faster"

rm -rf $TMP_DIR

exit $result


