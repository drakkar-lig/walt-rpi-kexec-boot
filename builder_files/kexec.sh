#!/bin/sh
set -e

# This script retrieve a kernel from NFS server
# and run kexec to load the new kernel

# redirect to console
exec 0</dev/console 1>/dev/console 2>/dev/console

on_error()
{
    echo "Dropping to a shell."
    sh
}

trap '[ "$?" -eq 0 ] || on_error' EXIT

cat > /root/retrieve-dhcp-options.sh << "END"
#!/bin/sh
set >> /root/env.txt
END
chmod +x /root/retrieve-dhcp-options.sh

cat > /root/hex2ascii.sh << "FIN"
#!/bin/sh
i=1
while [ $i -lt ${#1} ];
do
  tmp=$(echo $1 | cut -c$i,$((i+1)))
  echo -en "\x$tmp"
  i=$((i+2))
done
FIN
chmod +x /root/hex2ascii.sh

# Retrieve DHCP options in /root/env.txt
busybox udhcpc -s /root/retrieve-dhcp-options.sh

NFS_SERVER_HEX=$(cat /root/env.txt | grep opt138 | cut -d"'" -f2)
NFS_SERVER=$(/root/hex2ascii.sh $NFS_SERVER_HEX)
NFS_FS_PATH_HEX=$(cat /root/env.txt | grep opt140 | cut -d"'" -f2)
NFS_FS_PATH=$(/root/hex2ascii.sh $NFS_FS_PATH_HEX)

CMDLINE=$(cat /proc/cmdline)
ARGS="$CMDLINE nfs_server=$NFS_SERVER nfs_fs_path=$NFS_FS_PATH" 

echo "Mounting NFS" 
NFS_MOUNT=/nfs_mount
mkdir $NFS_MOUNT
mount $NFS_SERVER:$NFS_FS_PATH $NFS_MOUNT

# The kernel is at path /kernel of the filesystem.
echo "Running kexec ..."
kexec -l $NFS_MOUNT/kernel --initrd=/root/initrd.cpio.gz --append="$ARGS"
kexec -e

