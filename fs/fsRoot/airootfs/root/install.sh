#!/bin/bash

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    dialog --title "Error" --msgbox "Please run as root" 6 40
    exit 1
fi

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "ERROR: dialog is not installed. Please install it first."
    exit 1
fi

RANDOM_SECONDS=$((RANDOM % 60))

# Detect boot mode
if [ -d /sys/firmware/efi/efivars ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

# Welcome screen
dialog --title "Gopi OS Installer" --msgbox "Gopi OS Installer\n\nBoot Mode: $BOOT_MODE.\n\nPress OK to continue..." 12 50

# List available drives
mapfile -t DRIVES < <(lsblk -d -n -o NAME,SIZE,TYPE | grep disk)

if [ ${#DRIVES[@]} -eq 0 ]; then
    dialog --title "Error" --msgbox "No drives found!" 6 40
    exit 1
fi

# Prepare drive menu
DRIVE_MENU=()
for i in "${!DRIVES[@]}"; do
    DRIVE_MENU+=("$((i+1))" "${DRIVES[$i]}")
done

# Select drive
DRIVE_CHOICE=$(dialog --title "Drive Selection" --menu "Select installation drive:" 15 60 8 "${DRIVE_MENU[@]}" 3>&1 1>&2 2>&3)
if [ $? -ne 0 ]; then
    clear
    exit 1
fi

DRIVE_NAME=$(echo "${DRIVES[$((DRIVE_CHOICE-1))]}" | awk '{print $1}')
DRIVE="/dev/$DRIVE_NAME"

# Get hostname
while true; do
    HOSTNAME=$(dialog --title "System Name" --inputbox "Give a name to your System:" 8 50 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        clear
        exit 1
    fi
    if [ -n "$HOSTNAME" ]; then
        break
    else
        dialog --title "Error" --msgbox "Hostname cannot be empty." 6 40
    fi
done

# Get username
while true; do
    USERNAME=$(dialog --title "Username" --inputbox "Enter username:" 8 50 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        clear
        exit 1
    fi
    if [ -n "$USERNAME" ]; then
        break
    else
        dialog --title "Error" --msgbox "Username cannot be empty." 6 40
    fi
done

# Get password
while true; do
    PASSWORD=$(dialog --title "Password" --insecure --passwordbox "Enter password: \n\n Remember this password will be used for root and GPG key" 8 50 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        clear
        exit 1
    fi
    
    PASSWORD2=$(dialog --title "Password" --insecure --passwordbox "Confirm password:" 8 50 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        clear
        exit 1
    fi
    
    if [ "$PASSWORD" = "$PASSWORD2" ]; then
        if [ -n "$PASSWORD" ]; then
            break
        else
            dialog --title "Error" --msgbox "Password cannot be empty." 6 40
        fi
    else
        dialog --title "Error" --msgbox "Passwords do not match. Try again." 6 40
    fi
done

# Confirmation
dialog --title "Confirm Installation" --yesno "Ready to install Gopi OS\n\nDrive: $DRIVE\nHostname: $HOSTNAME\nUsername: $USERNAME\nBoot Mode: $BOOT_MODE\n\nWARNING: All data on $DRIVE will be erased!\n\nProceed with installation?" 15 60
if [ $? -ne 0 ]; then
    clear
    exit 1
fi

# Determine partition naming scheme
if [[ $DRIVE == *"nvme"* ]] || [[ $DRIVE == *"mmcblk"* ]]; then
    PART1="${DRIVE}p1"
    PART2="${DRIVE}p2"
else
    PART1="${DRIVE}1"
    PART2="${DRIVE}2"
fi

# Installation info
dialog --title "Installation Starting" --msgbox "it will take a while to install. \n then you will be able to use your stable system for 10 to 15 years. \n\n it is not mandatory to pay or purchase gopios, making some donation is helpful. \n you can use gopios at school, business, enterprise, anywhere.\n\n ETA: 9min ${RANDOM_SECONDS}s" 10 50

# Progress function
show_progress() {
    local percent=$1
    local message=$2
    echo "XXX"
    echo "$percent"
    echo "$message"
    echo "XXX"
}

# Start installation with progress dialog
(
    # Wiping drive
    show_progress 0 "Wiping drive..."
    wipefs -af "$DRIVE" >/dev/null 2>&1
    sgdisk --zap-all "$DRIVE" >/dev/null 2>&1
    
    # Creating partitions
    show_progress 5 "Creating partitions..."
    if [ "$BOOT_MODE" = "UEFI" ]; then
        parted -s "$DRIVE" mklabel gpt >/dev/null 2>&1
        parted -s "$DRIVE" mkpart ESP fat32 1MiB 701MiB >/dev/null 2>&1
        parted -s "$DRIVE" set 1 esp on >/dev/null 2>&1
        parted -s "$DRIVE" mkpart primary ext4 701MiB 100% >/dev/null 2>&1
    else
        parted -s "$DRIVE" mklabel msdos >/dev/null 2>&1
        parted -s "$DRIVE" mkpart primary ext4 1MiB 100% >/dev/null 2>&1
        parted -s "$DRIVE" set 1 boot on >/dev/null 2>&1
    fi
    
    sleep 2
    
    # Formatting partitions
    show_progress 2 "Formatting partitions..."
    if [ "$BOOT_MODE" = "UEFI" ]; then
        mkfs.fat -F32 "$PART1" >/dev/null 2>&1
        mkfs.ext4 -F -L gopios "$PART2" >/dev/null 2>&1
    else
        mkfs.ext4 -F -L gopios "$PART1" >/dev/null 2>&1
    fi
    
    # Mounting partitions
    show_progress 3 "Mounting partitions..."
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
        exit 1
    fi
    
    PROGRESS_START=25
    PROGRESS_END=70
    PROGRESS_RANGE=$((PROGRESS_END - PROGRESS_START))
    
    show_progress 4 "Installing base system (0/$TOTAL_PACKAGES packages)..."
    
    # Install packages with progress
    if [ -f /root/pacman.conf ]; then
        pacstrap -C /root/pacman.conf /mnt "${packages[@]}" 2>&1 | {
            INSTALLED=0
            while IFS= read -r line; do
                if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                    INSTALLED=$((INSTALLED + 1))
                    PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                    if [ $PROGRESS -gt $PROGRESS_END ]; then
                        PROGRESS=$PROGRESS_END
                    fi
                    show_progress "$PROGRESS" "Installing package $INSTALLED of $TOTAL_PACKAGES..."
                fi
            done
        }
    else
        pacstrap /mnt base linux linux-firmware 2>&1 | {
            INSTALLED=0
            while IFS= read -r line; do
                if [[ $line == *"installing"* ]] || [[ $line == *"upgrading"* ]]; then
                    INSTALLED=$((INSTALLED + 1))
                    PROGRESS=$((PROGRESS_START + (INSTALLED * PROGRESS_RANGE / TOTAL_PACKAGES)))
                    if [ $PROGRESS -gt $PROGRESS_END ]; then
                        PROGRESS=$PROGRESS_END
                    fi
                    show_progress "$PROGRESS" "Installing package $INSTALLED (estimated)..."
                fi
            done
        }
    fi
    
    show_progress 70 "Base system installed"
    sleep 1
    
    show_progress 75 "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
    
    show_progress 80 "Configuring system..."
    rsync -a /root/src/ /mnt/ 2>/dev/null
    
    # Replace placeholders in setup script
    sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /mnt/root/setup-gopios.sh
    sed -i "s/USERNAME_PLACEHOLDER/$USERNAME/g" /mnt/root/setup-gopios.sh
    sed -i "s/PASSWORD_PLACEHOLDER/$PASSWORD/g" /mnt/root/setup-gopios.sh
    sed -i "s/BOOT_MODE_PLACEHOLDER/$BOOT_MODE/g" /mnt/root/setup-gopios.sh
    sed -i "s|DRIVE_PLACEHOLDER|$DRIVE|g" /mnt/root/setup-gopios.sh
    
    chmod +x /mnt/root/setup-gopios.sh
    
    show_progress 85 "Running configuration..."
    arch-chroot /mnt /root/setup-gopios.sh 2>&1 | while IFS= read -r line; do
        show_progress 85 "Configuring system...\n$line"
    done
    
    show_progress 95 "Cleaning up..."
    rm /mnt/root/setup-gopios.sh
    
    umount -R /mnt
    
    show_progress 100 "Installation complete!"
    sleep 2

) | dialog --title "Installing Gopi OS" --gauge "Starting installation..." 8 70 0

# Completion screen
dialog --title "Installation Complete" --msgbox "Gopi OS Installation Complete!\n\nBoot Mode: $BOOT_MODE\nHostname: $HOSTNAME\nUsername: $USERNAME\n  press Enter..." 13 60

clear
poweroff