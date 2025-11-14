#!/bin/bash

# Find the ISO file in output directory
ISO_FILE=$(find ../out -name "*.iso" -type f -exec ls -t {} + | head -1)

if [[ -z "$ISO_FILE" ]]; then
    echo "❌ Error: No ISO file found in output directory"
    echo "💡 Make sure to build the ISO first with: ./build-iso.sh"
    exit 1
fi

if [[ ! -f "$ISO_FILE" ]]; then
    echo "❌ Error: ISO file not found: $ISO_FILE"
    exit 1
fi

# Extract ISO name without extension for disk name
ISO_BASENAME=$(basename "$ISO_FILE" .iso)
DISK_FILE="${ISO_BASENAME}.qcow2"

echo "🔍 Found ISO: $(basename "$ISO_FILE")"
echo "💾 File size: $(du -h "$ISO_FILE" | cut -f1)"
echo "💿 Virtual disk: $DISK_FILE"

# Create virtual disk if it doesn't exist
if [[ ! -f "$DISK_FILE" ]]; then
    echo "💿 Creating virtual disk (25GB)..."
    qemu-img create -f qcow2 "$DISK_FILE" 25G
    echo "✅ Virtual disk created: $DISK_FILE"
else
    echo "💿 Using existing virtual disk: $DISK_FILE"
    echo "💾 Disk size: $(du -h "$DISK_FILE" | cut -f1)"
fi

# Check if KVM is available
if [[ ! -e /dev/kvm ]]; then
    echo "⚠️  KVM not available, using slower TCG acceleration"
    ACCEL="tcg"
else
    ACCEL="kvm"
    echo "✅ KVM acceleration available"
fi

echo ""
echo "🚀 Starting QEMU VM..."
echo "📀 Booting from: $(basename "$ISO_FILE")"
echo "🎯 Acceleration: $ACCEL"
echo "💻 RAM: 4GB, CPU: 4 cores"
echo ""
echo "Press Ctrl+Alt+G to release mouse capture"
echo "Press Ctrl+Alt to capture mouse again"
echo ""

qemu-system-x86_64 \
  -cdrom "$ISO_FILE" \
  -drive "file=$DISK_FILE,if=virtio" \
  -m 4G \
  -smp 4 \
  -accel "$ACCEL" \
  -cpu host \
  -vga virtio \
  -display gtk \
  -boot menu=on \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0 \
  -rtc base=localtime \
  -usb \
  -device usb-tablet
