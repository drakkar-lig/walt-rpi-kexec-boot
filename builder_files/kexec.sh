#!/bin/sh
set -e

# This script retrieve a kernel from NFS server
# and run kexec to load the new kernel

# redirect to console
exec 0</dev/console 1>/dev/console 2>/dev/console

admin_sh()
{
    echo 'Starting a shell.'
    echo '(the node will be rebooted on exit.)'
    # see http://www.busybox.net/FAQ.html#job_control
    setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1' || sh
    reboot -f
}

# try to run /root/kexec_prepare.sh
retries_left=2
while [ 1 ]
do
    timeout -t 45 /root/kexec_prepare.sh && break || true
    echo 'An error occured.'
    if [ $retries_left -gt 0 ]
    then
        echo -n "Retrying in 5s... "
        echo "($retries_left retry(ies) before rebooting)"
    else
        echo "REBOOTING in 5s... "
    fi
    echo '-> or press <Enter> now for a shell'
    read -t 5 && admin_sh || true
    if [ $retries_left -gt 0 ]
    then
        echo "Retrying..."
        retries_left=$((retries_left-1))
    else
        echo "Too many attemps. Rebooting..."
        reboot -f
    fi
done

# start the new kernel
kexec -e

