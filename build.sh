#!/bin/bash

TIMESTAMP=$(date +%Y%m%d_%H%M)
WORK=/tmp/gopiWork_$TIMESTAMP
OS=../os_tmp
echo "Remove os directory"
rm -rf $OS
sleep 1
mkdir $OS
echo "Copy installer config"
# cp -rf configs/baseline ../os
sleep 1


echo "Copy Build"
cp -f pacmanLocalHost.conf $OS/pacman.conf
# cp -f fs/fsRoot/airootfs/root/pacman.conf $OS/pacman.conf
# cp -f profiledef.sh ../os/profiledef.sh
# cp -f packages.x86_64 ../os/packages.x86_64
# cp -f bootstrap_packages.x86_64 ../os/bootstrap_packages.x86_64
rsync -a fs/fsRoot/ $OS/

echo "Copy packages"
rsync -a ../repo/packages/ $OS/airootfs/root/repo/packages/

sleep 1
echo "gopios Sync"
# rsync -a ../gopios/repo/ ../os/airootfs/root/repo/
rsync -a ../gopios/src $OS/airootfs/root/
sleep 1



sleep 1
echo "Building"

# Create work directory if it doesn't exist
mkdir -p "$WORK"

# Check if already mounted and unmount if needed
if mountpoint -q "$WORK"; then
    echo "Unmounting existing filesystem at $WORK"
    umount "$WORK" || true
fi

# Mount tmpfs
echo "Mounting tmpfs at $WORK"
if ! mount -t tmpfs -o size=15G tmpfs "$WORK"; then
    echo "Failed to mount tmpfs, continuing with regular directory"
    # Continue without tmpfs if mounting fails
else
    TRAP_CMD="umount \"$WORK\" 2>/dev/null || true"
    trap "$TRAP_CMD" EXIT INT TERM
fi

# Build the ISO
mkarchiso -v -r -w "$WORK" -o ../out "$OS"

# Cleanup
if mountpoint -q "$WORK"; then
    echo "Unmounting tmpfs from $WORK"
    umount "$WORK" || true
fi

