#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

RANDOM_SECONDS=$((RANDOM % 60))

# Detect boot mode
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

clear
echo "========================================"
echo "       Gopi OS Installer"
echo "========================================"
echo "Boot Mode: $BOOT_MODE"
echo ""
echo "GUI NT Kernel installer in future."
echo ""
#read -p "Press Enter to continue..."

# List available drives
echo ""
echo "========================================"
echo "Available Drives:"
echo "========================================"
mapfile -t DRIVES < <(lsblk -d -n -o NAME,SIZE,TYPE | grep disk)

if [ ${#DRIVES[@]} -eq 0 ]; then
    echo "ERROR: No drives found!"
    exit 1
fi

# Display drives with numbers
for i in "${!DRIVES[@]}"; do
    echo "$((i+1))) ${DRIVES[$i]}"
done

# Select drive
while true; do
    echo ""
    read -p "Select drive number (1-${#DRIVES[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#DRIVES[@]}" ]; then
        DRIVE_NAME=$(echo "${DRIVES[$((choice-1))]}" | awk '{print $1}')
        DRIVE="/dev/$DRIVE_NAME"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done



# Get hostname
echo ""
while true; do
    read -p "Give a name to your System: " HOSTNAME
    if [ -n "$HOSTNAME" ]; then
        break
    else
        echo "Hostname cannot be empty."
    fi
done

# Get username
echo ""
while true; do
    read -p "Enter username: " USERNAME
    if [ -n "$USERNAME" ]; then
        break
    else
        echo "Username cannot be empty."
    fi
done

# Get password
echo ""
while true; do
    read -s -p "Enter password: " PASSWORD
    echo ""
    read -s -p "Confirm password: " PASSWORD2
    echo ""
    
    if [ "$PASSWORD" = "$PASSWORD2" ]; then
        if [ -n "$PASSWORD" ]; then
            break
        else
            echo "Password cannot be empty."
        fi
    else
        echo "Passwords do not match. Try again."
        echo ""
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

echo ""
echo "========================================"
echo "Starting Installation"
echo "========================================"
echo "Somehow the installer skips 69%"
echo "Just Relax while installing."
echo "ETA: 8min ${RANDOM_SECONDS}s"
echo ""

# Wiping drive
echo "[0%] Wiping drive..."
wipefs -af "$DRIVE" >/dev/null
sgdisk --zap-all "$DRIVE" >/dev/null

# Creating partitions
echo "[0%] Creating partitions..."
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

# Formatting partitions
echo "[0%] Formatting partitions..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mkfs.fat -F32 "$PART1" >/dev/null
    mkfs.ext4 -F -L gopios "$PART2" >/dev/null
else
    mkfs.ext4 -F -L gopios "$PART1" >/dev/null
fi

# Mounting partitions
echo "[4%] Mounting partitions..."
if [ "$BOOT_MODE" = "UEFI" ]; then
    mount "$PART2" /mnt
    mkdir -p /mnt/boot
    mount "$PART1" /mnt/boot
else
    mount "$PART1" /mnt
fi

# Count total packages
if [ -f /root/pacman.conf ]; then
    mapfile -t packages < /root/gopi.packages.all.amd64
    TOTAL_PACKAGES=${#packages[@]}
else
    TOTAL_PACKAGES=150
fi

INSTALLED_PACKAGES=0
PROGRESS_START=25
PROGRESS_END=70
PROGRESS_RANGE=$((PROGRESS_END - PROGRESS_START))

echo "[8%] Installing base system (0/$TOTAL_PACKAGES packages)..."

# Install packages with progress
if [ -f /root/pacman.conf ]; then
    pacstrap -C /root/pacman.conf /mnt "${packages[@]}" | {
        INSTALLED=0
        while IFS= read -r line; do
            if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                INSTALLED=$((INSTALLED + 1))
                PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                if [ $PROGRESS -gt $PROGRESS_END ]; then
                    PROGRESS=$PROGRESS_END
                fi
                echo "[$PROGRESS%] Installing package $INSTALLED of $TOTAL_PACKAGES..."
            fi
        done
    }
else
    pacstrap /mnt base linux linux-firmware | {
        INSTALLED=0
        while IFS= read -r line; do
            if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                INSTALLED=$((INSTALLED + 1))
                PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                if [ $PROGRESS -gt $PROGRESS_END ]; then
                    PROGRESS=$PROGRESS_END
                fi
                echo "[$PROGRESS%] Installing package $INSTALLED (estimated)..."
            fi
        done
    }
fi

echo "[70%] Base system installed"

echo "[75%] Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "[80%] Configuring system..."

rsync -a /root/src/ /mnt/

# Replace placeholders in setup script
sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /mnt/root/setup-gopios.sh
sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" /mnt/root/setup-gopios.sh
sed -i "s/PASSWORD_PLACEHOLDER/$PASSWORD/g" /mnt/root/setup-gopios.sh
sed -i "s/BOOT_MODE_PLACEHOLDER/$BOOT_MODE/g" /mnt/root/setup-gopios.sh
sed -i "s|DRIVE_PLACEHOLDER|$DRIVE|g" /mnt/root/setup-gopios.sh

chmod +x /mnt/root/setup-gopios.sh

echo "[85%] Running configuration..."
arch-chroot /mnt /root/setup-gopios.sh

echo "[95%] Cleaning up..."
rm /mnt/root/setup-gopios.sh

# chattr -i /usr/bin/pacman
umount -R /mnt

echo "[100%] Installation complete!"
echo ""
echo "========================================"
echo "Gopi OS Installation Complete"
echo "========================================"
echo "Boot Mode: $BOOT_MODE"
echo "Hostname: $HOSTNAME"
echo "Username: $USERNAME"
echo ""
echo "Remove installation media and press Enter to reboot..."
read -p ""
reboot