#!/bin/sh
set -e

admin_sh()
{
    echo 'Starting a shell.'
    echo '(the node will be rebooted on exit.)'
    # see http://www.busybox.net/FAQ.html#job_control
    setsid sh -c 'exec sh </dev/tty1 >/dev/tty1 2>&1' || sh
    reboot -f
}

run_original_init()
{
    echo "*** Running original init ***" 
    # now we start the orginal init binary
    # rooting the filesystem in fs_union
    cd /tmp/inmemory/fs_union
    exec chroot . sbin/init
}

# try to run /union_init_prepare.sh
while [ 1 ]
do
    timeout -t 10 /union_init_prepare.sh && break || true
    echo 'An error occured.'
    echo 'Rebooting in 5s... (press <Enter> for a shell)'
    read -t 5 && admin_sh || reboot -f
done

# pass to regular init
run_original_init

