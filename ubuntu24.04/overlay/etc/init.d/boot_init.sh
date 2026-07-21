#!/bin/bash -e

### BEGIN INIT INFO
# Provides:          LubanCat
# Required-Start:
# Required-Stop:
# Default-Start:
# Default-Stop:
# Short-Description:
# Description:       This script initializes custom services or configurations at boot time.
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

board_info() {

    SWITCH_DTB=0

    case "$SOC_type" in

    rk3588|rk3588s)

        case "$BOARD_MODEL" in

            "rk3588-ydkj-v2")
                BOARD_NAME="rk3588-ydkj-v2"
                BOARD_DTB="rk3588-ydkj-v2.dtb"
                BOARD_uEnv="uEnvrk3588-ydkj-v2.txt"
                SWITCH_DTB=1
                ;;

            "rk3588-elf")
                BOARD_NAME="rk3588-elf"
                BOARD_DTB="rk3588-elf.dtb"
                BOARD_uEnv="uEnvELF.txt"
                SWITCH_DTB=1
                ;;

        esac
        ;;
    esac

    if [ "$SWITCH_DTB" -eq 0 ]; then
        echo "Unknown board: $BOARD_MODEL"
        echo "Keep current DTB and uEnv."

        BOARD_NAME="$BOARD_MODEL"
        BOARD_DTB=""
        BOARD_uEnv=""
    fi

    echo "BOARD_NAME : $BOARD_NAME"
    echo "BOARD_DTB  : $BOARD_DTB"
    echo "BOARD_uEnv : $BOARD_uEnv"
}

board_detect() {

    SOC_type=$(tr '\0' '\n' < /proc/device-tree/compatible | sed -n '2p' | cut -d, -f2)
    BOARD_MODEL=$(tr -d '\0' < /proc/device-tree/model)

    echo "SOC_type    : $SOC_type"
    echo "BOARD_MODEL : $BOARD_MODEL"
}

board_detect
board_info

#
# 等待 boot 分区节点
#
until [ -e "/dev/disk/by-partlabel/boot" ]
do
    echo "wait /dev/disk/by-partlabel/boot"
    sleep 0.1
done

if [ ! -e "/boot/boot_init" ]; then

    if [ ! -e "/dev/disk/by-partlabel/userdata" ]; then

        #
        # 固定挂载 boot 分区
        #
        if ! mountpoint -q /boot; then
            mount /dev/mmcblk0p2 /boot
            grep -q "/boot" /etc/fstab || \
                echo "/dev/mmcblk0p2  /boot  ext2  defaults  0 2" >> /etc/fstab
        fi

        service lightdm stop || echo "skip error"

        apt install -fy --allow-downgrades /boot/kerneldeb/* || true

        apt-mark hold \
            linux-headers-$(uname -r) \
            linux-image-$(uname -r) || true

        #
        # 已识别板型才切换 DTB
        #
        if [ "$SWITCH_DTB" -eq 1 ]; then

            echo "Switch DTB -> $BOARD_DTB"

            ln -sf "dtb/$BOARD_DTB" /boot/rk-kernel.dtb
            ln -sf "$BOARD_uEnv" /boot/uEnv/uEnv.txt

        else

            echo "Keep current DTB/uEnv."

        fi

        touch /boot/boot_init

        rm -f /boot/kerneldeb/*
        cp -f /boot/logo_kernel.bmp /boot/logo.bmp

        sync
        reboot

    else

        grep -q "/oem" /etc/fstab || \
            echo "PARTLABEL=oem  /oem  ext2  defaults  0 2" >> /etc/fstab

        grep -q "/userdata" /etc/fstab || \
            echo "PARTLABEL=userdata  /userdata  ext2  defaults  0 2" >> /etc/fstab

        touch /boot/boot_init

    fi

fi