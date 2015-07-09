#!/bin/sh
set -e

# This script retrieve a kernel from NFS server
# and run kexec to load the new kernel

# redirect to console
exec 0</dev/console 1>/dev/console 2>/dev/console

# in case of error we wait a few seconds.
# If the user wants to start a shell or 
# reboot the node, he must type <Enter>
# within this small delay.
# Otherwise we retry the script after this
# delay.
# The content of this script has to take into
# account the fact that it be partially executed 
# several times.
on_error()
{
    echo 'An error occured.'
    echo 'Retrying in 5s... (press <Enter> for a shell)'
    read -t 5 && admin_sh || true
    echo "Retrying..."
    $0 $*
}

admin_sh()
{
    echo 'Starting a shell.'
    echo '(the node will be rebooted on exit.)'
    # see http://www.busybox.net/FAQ.html#job_control
    setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1' || sh
    reboot -f
}

# given an hexadecimal string, put a \x before
# each pair of hexadecimal characters, and 
# evaluate to retrieve the hidden chars.
hex2ascii()
{
    echo -en "$(
        echo -n "$1" | sed -e 's/\(..\)/\\x\1/g'
    )"
}

trap '[ "$?" -eq 0 ] || on_error' EXIT

# prepare dhcp options retrieval
cat > /root/retrieve-dhcp-options.sh << "END"
#!/bin/sh
set > /root/env.txt
END
chmod +x /root/retrieve-dhcp-options.sh

# wait for kernel to detect the network interface
# and enable it
while [ 1 ]
do
    ip link set dev eth0 up 2>/dev/null && break || usleep 200000
done

# call DHCP client
# -n & -q: exit if failed / succeeded (no background process kept)
# -s: retrieve options in /root/env.txt
udhcpc -nq -t 10 -s /root/retrieve-dhcp-options.sh

# get and process dhcp option variables
. /root/env.txt
IP="$ip/$mask"
NFS_SERVER=$(hex2ascii $opt138)
NFS_FS_PATH=$(hex2ascii $opt140)

CMDLINE=$(cat /proc/cmdline)
ARGS="$CMDLINE nfs_server=$NFS_SERVER nfs_fs_path=$NFS_FS_PATH"
ARGS="$ARGS node_ip=$IP node_hostname=$hostname"

# set ip if not done yet
ip addr | grep -q $IP || ip addr add $IP dev eth0

# mount the NFS filesystem if not done yet
echo "Mounting NFS" 
NFS_MOUNT=/nfs_mount
mkdir -p $NFS_MOUNT
mountpoint -q $NFS_MOUNT || mount $NFS_SERVER:$NFS_FS_PATH $NFS_MOUNT

# The kernel is at path /kernel of the filesystem.
echo "Running kexec ..."
kexec -l $NFS_MOUNT/kernel --initrd=/root/initrd.cpio.gz --append="$ARGS"
kexec -e

