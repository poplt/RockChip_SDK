#!/bin/bash -e

SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)

ROOTFS_FILE="$SCRIPT_DIR/openkylin-V2.tar.xz"
BACK_FILE="$SCRIPT_DIR/back_base_file/openkylin-V2.tar.xz"

echo "=========================================="
echo "      Build openKylin base rootfs"
echo "=========================================="

# 检查 openkylin-V2.tar.xz
if [ ! -f "$ROOTFS_FILE" ]; then

    echo "No $ROOTFS_FILE"

    if [ -f "$BACK_FILE" ]; then

        echo "Copy backup rootfs:"
        echo "$BACK_FILE"

        cp -v "$BACK_FILE" "$ROOTFS_FILE"

    else

        echo "ERROR: backup file not found:"
        echo "$BACK_FILE"
        exit 1

    fi

else

    echo "Found:"
    echo "$ROOTFS_FILE"

fi


echo "openkylin base rootfs ready"