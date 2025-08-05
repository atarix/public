#!/bin/bash

# Variables (set these before running)
disk_device=${disk_device:-/dev/sdc1}   # Example: /dev/sdc
partition=${partition:-1}              # Default partition number

# Wait for the disk to be attached
while [ ! -e "$disk_device" ]; do
  sleep 1
done

# Partition the disk (GPT, single partition)
parted --script "$disk_device" mklabel gpt
parted --script "$disk_device" mkpart primary ext4 0% 100%

# Wait for partition to be available
part_device="${disk_device}-part${partition}"
if [ ! -e "$part_device" ]; then
  part_device="${disk_device}${partition}"
  while [ ! -e "$part_device" ]; do
    sleep 1
  done
fi

# Format the partition if not already formatted
if ! blkid "$part_device" | grep -q ext4; then
  mkfs.ext4 "$part_device"
fi

# Mount the partition (example mount point)
mount_point="/mnt"
mkdir -p "$mount_point"
mount "$part_device" "$mount_point"

# Grow partition and filesystem
growpart "$disk_device" "$partition"
resize2fs -f "$part_device"

# Optional: Add to /etc/fstab for persistence
uuid=$(blkid -s UUID -o value "$part_device")
grep -q "$uuid" /etc/fstab || echo "UUID=$uuid $mount_point ext4 defaults,nofail 0 2" >> /etc/fstab

echo "Disk setup complete: $part_device mounted at $mount_point"