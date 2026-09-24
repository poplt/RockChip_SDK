#!/bin/bash -e


# =====================================
# 获取脚本所在目录
# =====================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


# =====================================
# rootfs目录
# =====================================

TARGET_ROOTFS_DIR="${SCRIPT_DIR}/binary"


# =====================================
# 用户配置
# =====================================

OLD_USERNAME="topeet"

USERNAME="cat"

PASSWORD="poplt"


# =====================================
# Kconfig变量
# =====================================

ARCH=${RK_OPENKYLIN_ARCH:-arm64}

ROOTFS_FILE=${RK_OPENKYLIN_ROOTFS_FILE:-"${SCRIPT_DIR}/openkylin-V2.tar.xz"}


# =====================================
# 显示信息
# =====================================

echo "----------------------------------------"
echo "openKylin rootfs"
echo "ARCH      : ${ARCH}"
echo "ROOTFS    : ${ROOTFS_FILE}"
echo "----------------------------------------"


# =====================================
# 删除旧rootfs
# =====================================

echo -e "\033[47;36m Remove old rootfs.................... \033[0m"

sudo rm -rf "${TARGET_ROOTFS_DIR}"


# =====================================
# 解压openKylin基础rootfs
# =====================================

echo -e "\033[47;36m Extract openKylin rootfs.................... \033[0m"


if [ ! -f "${ROOTFS_FILE}" ]; then

    echo "ERROR: ${ROOTFS_FILE} not exist!"

    exit 1

fi


sudo tar -xf "${ROOTFS_FILE}"


# =====================================
# 复制overlay
# =====================================

echo -e "\033[47;36m Copy overlay files.................... \033[0m"


if [ -d "${SCRIPT_DIR}/overlay" ]; then

    sudo cp -rfp "${SCRIPT_DIR}/overlay/"* \
        "${TARGET_ROOTFS_DIR}/"

fi


# =====================================
# firmware
# =====================================

echo -e "\033[47;36m Copy firmware overlay.................... \033[0m"


if [ -d "${SCRIPT_DIR}/overlay-firmware" ]; then

    sudo cp -rfp "${SCRIPT_DIR}/overlay-firmware/"* \
        "${TARGET_ROOTFS_DIR}/"

fi


# =====================================
# DNS
# =====================================

sudo cp -L /etc/resolv.conf \
    "${TARGET_ROOTFS_DIR}/etc/resolv.conf"


# =====================================
# mount rootfs
# =====================================

echo -e "\033[47;36m Mount rootfs.................... \033[0m"


cd "${SCRIPT_DIR}"

./mount.sh -m "${TARGET_ROOTFS_DIR}"


# =====================================
# 错误处理
# =====================================

finish()
{
    echo "========================================"
    echo "Unmount rootfs"
    echo "========================================"

    cd "${SCRIPT_DIR}"

    ./mount.sh -u "${TARGET_ROOTFS_DIR}" || true

    exit 1
}

trap finish ERR


# =====================================
# Change root
# =====================================

echo -e "\033[47;36m Change root.................... \033[0m"


cat << EOF | sudo chroot "${TARGET_ROOTFS_DIR}" /bin/bash

export LC_ALL=C.UTF-8


# =====================================
# 修改用户
# =====================================

echo "Modify user ${OLD_USERNAME} -> ${USERNAME}"


if id ${USERNAME} >/dev/null 2>&1

then

    echo "${USERNAME} already exist"

else

    if id ${OLD_USERNAME} >/dev/null 2>&1

    then

        usermod \
            -l ${USERNAME} \
            ${OLD_USERNAME}


        usermod \
            -d /home/${USERNAME} \
            -m \
            ${USERNAME}

    fi

fi


# =====================================
# 用户描述
# =====================================

if id ${USERNAME} >/dev/null 2>&1

then

    usermod \
        -c "${USERNAME}" \
        ${USERNAME}

fi


# =====================================
# 密码
# =====================================

echo "${USERNAME}:${PASSWORD}" | chpasswd


# =====================================
# sudo权限
# =====================================

usermod -aG sudo ${USERNAME}

usermod -aG video ${USERNAME}

usermod -aG render ${USERNAME}

usermod -aG audio ${USERNAME}

usermod -aG dialout ${USERNAME}

usermod -aG input ${USERNAME}

usermod -aG plugdev ${USERNAME}


# =====================================
# root密码
# =====================================

echo "root:${PASSWORD}" | chpasswd

passwd -u root || true


# =====================================
# sudo免密
# =====================================

if ! grep -q "^%sudo" /etc/sudoers

then

    echo "%sudo ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

fi


# =====================================
# hostname
# =====================================

echo "cat" > /etc/hostname


# =====================================
# 时区
# =====================================

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime


# =====================================
# 清理apt
# =====================================

apt clean

rm -rf /var/lib/apt/lists/*


# =====================================
# 同步
# =====================================

sync

EOF


# =====================================
# umount
# =====================================

echo -e "\033[47;36m Umount rootfs.................... \033[0m"


cd "${SCRIPT_DIR}"

./mount.sh -u "${TARGET_ROOTFS_DIR}"


# =====================================
# 构建完成
# =====================================

echo "========================================"
echo "Rootfs build finished"
echo "========================================"


# =====================================
# build ext4
# =====================================

echo -e "\033[47;36m build_ext4 rootfs.................... \033[0m"


source ./mk-image.sh