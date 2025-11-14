#!/bin/bash

set -e

trap 'echo "Exiting..."; exit 0' INT

INPUT="../gopios/gopi.packages.amd64"
OUTPUT="fs/fsRoot/airootfs/root/gopi.packages.all.amd64"
TEMP="../gopios/gopi.packages.all.amd64.list"
TARGET_DIR="../../repo/packages/"

# Clear output file
echo "removing" "$OUTPUT" and "$TEMP"
sleep 2
> "$OUTPUT"
> "$TEMP"
rm -rf "$TARGET_DIR"

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    
    # Remove inline comments and trim whitespace
    package=$(echo "$line" | sed 's/#.*//' | xargs)
    
    # Skip if empty after processing
    [ -z "$package" ] && continue
    
    # Check if it's a group
    if pacman -Sgq "$package" &>/dev/null; then
        echo "Expanding group: $package"
        pacman -Sgq "$package" >> "$TEMP"
    else
        # It's a regular package
        echo "Adding package: $package"
        echo "$package" >> "$TEMP"
    fi
done < "$INPUT"

# Now get all dependencies for collected packages
echo "Getting all dependencies..."
{
    # First, output all the original packages
    sort -u "$TEMP"
    
    # Then get their dependencies
    sort -u "$TEMP" | while read -r pkg; do
        pactree -slu "$pkg" 2>/dev/null
    done
} | sort -u > "$OUTPUT"


echo "Complete package list with dependencies written to $OUTPUT"
sleep 2

echo "Removing old packages..."
sudo rm -rf /var/cache/pacman/pkg/*

echo "Downloading packages to host cache..."

sudo pacman -Syw --noconfirm $(cat "$OUTPUT")
cp "$OUTPUT" ../gopios/  # just to have a copy of the list


mkdir -p "$TARGET_DIR"
echo "Copying packages to $TARGET_DIR..."
sudo cp -n /var/cache/pacman/pkg/*.pkg.tar.zst "$TARGET_DIR" 2>/dev/null || true

echo "Updating package database in $TARGET_DIR..."
(cd "$TARGET_DIR" && sudo repo-add gopi.db.tar.gz *.pkg.tar.zst 2>/dev/null || true)

echo "Packages processed and copied to $TARGET_DIR"

