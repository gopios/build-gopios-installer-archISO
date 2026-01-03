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

rm -f $OS/airootfs/root/root/install.sh
mv $OS/airootfs/root/install-dev.sh $OS/airootfs/root/install.sh
sleep 1
echo "Building"

mount -t tmpfs -o size=15G tmpfs $WORK
mkarchiso -v -r -w $WORK -o ../out $OS

sleep 3
umount $WORK

