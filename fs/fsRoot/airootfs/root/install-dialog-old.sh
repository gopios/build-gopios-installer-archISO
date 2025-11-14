#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Installing dialog..."
    pacman -Sy --noconfirm dialog
fi

HEIGHT=30
WIDTH=90
RANDOM_SECONDS=$((RANDOM % 60))
# Detect boot mode
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

dialog --title "Gopi OS Installer" --msgbox "Boot Mode: $BOOT_MODE\n\n GUI NT Kernel installer in future." $HEIGHT $WIDTH

# List available drives and create menu options
mapfile -t DRIVES < <(lsblk -d -n -o NAME,SIZE,TYPE | grep disk | awk '{print $1 " " $2}')

if [ ${#DRIVES[@]} -eq 0 ]; then
    dialog --title "Error" --msgbox "No drives found!" $HEIGHT $WIDTH
    clear
    exit 1
fi

# Build dialog menu options
DRIVE_OPTIONS=()
for drive in "${DRIVES[@]}"; do
    DRIVE_OPTIONS+=("$drive" "")
done

# Select drive
DRIVE=$(dialog --title "Select Drive" --menu "Choose a drive to install:" $HEIGHT $WIDTH 10 "${DRIVE_OPTIONS[@]}" 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus != 0 ]; then
    clear
    exit 0
fi

DRIVE="/dev/$(echo $DRIVE | awk '{print $1}')"

# Confirm wipe
dialog --title "WARNING" --yesno "This will COMPLETELY WIPE $DRIVE\n\nAre you sure you want to continue?" $HEIGHT $WIDTH
if [ $? != 0 ]; then
    clear
    exit 0
fi

HOSTNAME=$(dialog --title "Hostname" --inputbox "Give a name to your System:" $HEIGHT $WIDTH 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus != 0 ]; then
    clear
    exit 0
fi

USERNAME=$(dialog --title "Username" --inputbox "Enter username:" $HEIGHT $WIDTH 3>&1 1>&2 2>&3)
exitstatus=$?
if [ $exitstatus != 0 ]; then
    clear
    exit 0
fi

while true; do
    PASSWORD=$(dialog --title "Password" --insecure --passwordbox "Enter password:" $HEIGHT $WIDTH 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus != 0 ]; then
        clear
        exit 0
    fi
    
    PASSWORD2=$(dialog --title "Password" --insecure --passwordbox "Confirm password:" $HEIGHT $WIDTH 3>&1 1>&2 2>&3)
    exitstatus=$?
    if [ $exitstatus != 0 ]; then
        clear
        exit 0
    fi
    
    if [ "$PASSWORD" = "$PASSWORD2" ]; then
        break
    else
        dialog --title "Error" --msgbox "Passwords do not match. Try again." $HEIGHT $WIDTH
    fi
done

# Determine partition naming scheme
if [[ $DRIVE == *"nvme"* ]] || [[ $DRIVE == *"mmcblk"* ]]; then
    PART1="${DRIVE}p1"
    PART2="${DRIVE}p2"
else
    PART1="${DRIVE}1"
    PART2="${DRIVE}2"
fi

(
echo "0" ; echo "# Wiping drive..."
wipefs -af "$DRIVE"
sgdisk --zap-all "$DRIVE"

echo "0" ; echo "# Creating partitions..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    parted -s "$DRIVE" mklabel gpt
    parted -s "$DRIVE" mkpart ESP fat32 1MiB 701MiB
    parted -s "$DRIVE" set 1 esp on
    parted -s "$DRIVE" mkpart primary ext4 701MiB 100%
else
    parted -s "$DRIVE" mklabel msdos
    parted -s "$DRIVE" mkpart primary ext4 1MiB 100%
    parted -s "$DRIVE" set 1 boot on
fi

sleep 2

echo "0" ; echo "# Formatting partitions..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "$PART1"
    mkfs.ext4 -F -L gopios "$PART2"
else
    mkfs.ext4 -F -L gopios "$PART1"
fi

echo "4"
echo "# Mounting partitions..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mount "$PART2" /mnt
    mkdir -p /mnt/boot
    mount "$PART1" /mnt/boot
else
    mount "$PART1" /mnt
fi

# Count total packages first
if [ -f /root/pacman.conf ]; then
    mapfile -t packages < /root/gopi.packages.all.amd64
    TOTAL_PACKAGES=${#packages[@]}
else
    # Estimate package count for base installation (approximate)
    TOTAL_PACKAGES=150
fi

INSTALLED_PACKAGES=0
PROGRESS_START=25
PROGRESS_END=70
PROGRESS_RANGE=$((PROGRESS_END - PROGRESS_START))

echo "8"
echo "# Installing base system (0/$TOTAL_PACKAGES packages)..."

if [ -f /root/pacman.conf ]; then
    pacstrap -C /root/pacman.conf /mnt "${packages[@]}" 2>&1 | {
        INSTALLED=0
        LAST_PROGRESS=25
        LAST_MESSAGE="Installing base system (0/$TOTAL_PACKAGES packages)..."
        while IFS= read -r line; do
            if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                INSTALLED=$((INSTALLED + 1))
                LAST_PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                if [ $LAST_PROGRESS -gt $PROGRESS_END ]; then
                    LAST_PROGRESS=$PROGRESS_END
                fi
                LAST_MESSAGE="Installing package $INSTALLED of $TOTAL_PACKAGES..."
            fi
            echo "$LAST_PROGRESS"
            echo "# $LAST_MESSAGE"
        done
    }
else
    pacstrap /mnt base linux linux-firmware 2>&1 | {
        INSTALLED=0
        LAST_PROGRESS=25
        LAST_MESSAGE="Installing base system (estimated $TOTAL_PACKAGES packages)..."
        while IFS= read -r line; do
            if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                INSTALLED=$((INSTALLED + 1))
                LAST_PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                if [ $LAST_PROGRESS -gt $PROGRESS_END ]; then
                    LAST_PROGRESS=$PROGRESS_END
                fi
                LAST_MESSAGE="Installing package $INSTALLED (estimated)..."
            fi
            echo "$LAST_PROGRESS"
            echo "# $LAST_MESSAGE"
        done
    }
fi

echo "70"
echo "# Base system installed"

echo "75" ; echo "# Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "80" ; echo "# Configuring system..."

rsync -a /root/src/ /mnt/

# Replace placeholders in setup script
sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /mnt/root/setup-gopios.sh
sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" /mnt/root/setup-gopios.sh
sed -i "s/PASSWORD_PLACEHOLDER/$PASSWORD/g" /mnt/root/setup-gopios.sh
sed -i "s/BOOT_MODE_PLACEHOLDER/$BOOT_MODE/g" /mnt/root/setup-gopios.sh
sed -i "s|DRIVE_PLACEHOLDER|$DRIVE|g" /mnt/root/setup-gopios.sh

chmod +x /mnt/root/setup-gopios.sh

echo "85" ; echo "# Running configuration..."
arch-chroot /mnt /root/setup-gopios.sh

echo "95" ; echo "# Cleaning up..."
rm /mnt/root/setup-gopios.sh

umount -R /mnt

echo "100"
echo "# Installation complete..."
) | dialog --title "Installing Gopi OS" --gauge "Somehow the installer skips 69%\n Just Relax while installing.\n ETA: 8min ${RANDOM_SECONDS}s ." $HEIGHT $WIDTH 0

dialog --title "Gopi OS Installation Complete" --msgbox "Gopi OS installed !\n\nBoot Mode: $BOOT_MODE\nHostname: $HOSTNAME\nUsername: $USERNAME\n\nRemove installation media and press Enter to reboot..." $HEIGHT $WIDTH

clear
read -p "Press Enter to reboot..."
reboot