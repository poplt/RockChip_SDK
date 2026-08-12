#!/bin/bash -e


# =====================================
# rootfs目录
# =====================================

TARGET_ROOTFS_DIR="binary"


# 原用户和目标用户

OLD_USERNAME="topeet"

USERNAME="cat"

PASSWORD="poplt"




# =====================================
# 初始化rootfs
#
# 选择是否删除旧binary
#
# 1: 删除旧rootfs重新解压
# 2: 保留旧rootfs继续构建
# =====================================


BUILD_MODE=1


if [ -d "${TARGET_ROOTFS_DIR}" ]; then

    echo "----------------------------------------"
    echo "binary already exist"
    echo "检测到已有rootfs"
    echo ""
    echo "[1] Remove old rootfs and extract again"
    echo "    删除旧rootfs重新解压"
    echo ""
    echo "[2] Keep old rootfs"
    echo "    保留当前rootfs继续构建"
    echo "----------------------------------------"

    read -p "Select option [1-2]: " input


    case $input in

        1)
            BUILD_MODE=1
            echo "Remove old rootfs..."
            sudo rm -rf ${TARGET_ROOTFS_DIR}
            ;;

        2)
            BUILD_MODE=2
            echo "Keep old rootfs..."
            ;;

        *)
            echo "Invalid option"
            exit 1
            ;;

    esac

fi



# =====================================
# 解压openkylin基础rootfs
# =====================================


if [ "${BUILD_MODE}" == "1" ]; then


    echo -e "\033[47;36m Extract openkylin rootfs.................... \033[0m"


    if [ ! -f openkylin-V2.tar.xz ]; then

        echo "ERROR: openkylin-V2.tar.xz not exist!"

        exit 1

    fi


    sudo tar -xf openkylin-V2.tar.xz


else

    echo -e "\033[47;36m Skip extract rootfs.................... \033[0m"

fi


# =====================================
# 复制overlay
#
# overlay/etc  -> binary/etc
# overlay/usr  -> binary/usr
#
# =====================================


echo -e "\033[47;36m Copy overlay files.................... \033[0m"


if [ -d overlay ]; then

    sudo cp -rfp overlay/* \
    ${TARGET_ROOTFS_DIR}/

fi





# =====================================
# 复制firmware
#
# overlay-firmware/usr
#
#        |
#        v
#
# binary/usr
#
# =====================================


echo -e "\033[47;36m Copy firmware overlay.................... \033[0m"


if [ -d overlay-firmware ]; then

    sudo cp -rfp overlay-firmware/* \
    ${TARGET_ROOTFS_DIR}/

fi






# =====================================
# DNS配置
# =====================================


sudo cp -L /etc/resolv.conf \
${TARGET_ROOTFS_DIR}/etc/resolv.conf






# =====================================
# 挂载chroot环境
# =====================================


echo -e "\033[47;36m Mount rootfs.................... \033[0m"



./mount.sh -m ${TARGET_ROOTFS_DIR}





finish()
{

    echo "Unmount rootfs"


    ./mount.sh -u ${TARGET_ROOTFS_DIR}


    exit 1

}



trap finish ERR






echo -e "\033[47;36m Change root.................... \033[0m"






cat <<EOF | sudo chroot ${TARGET_ROOTFS_DIR} /bin/bash



export LC_ALL=C.UTF-8





echo "Modify user ${OLD_USERNAME} to ${USERNAME}"





# =====================================
# 修改默认用户
# =====================================

# =====================================
# 修改默认用户
# =====================================


if id ${USERNAME} >/dev/null 2>&1

then

    echo "${USERNAME} already exist"

else

    if id ${OLD_USERNAME} >/dev/null 2>&1
    then

        echo "Rename ${OLD_USERNAME} -> ${USERNAME}"


        # 修改用户名
        usermod \
        -l ${USERNAME} \
        ${OLD_USERNAME}


        # 修改home目录
        usermod \
        -d /home/${USERNAME} \
        -m \
        ${USERNAME}


    else

        echo "User ${OLD_USERNAME} not exist"

    fi

fi


# 修改用户描述字段
if id ${USERNAME} >/dev/null 2>&1
then

    usermod \
    -c "${USERNAME}" \
    ${USERNAME}

fi



# =====================================
# 修改用户密码
# =====================================


echo "${USERNAME}:${PASSWORD}" | chpasswd






# =====================================
# 添加用户权限
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



# 解锁root

passwd -u root || true





# =====================================
# sudo免密码
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
# 清理
# =====================================


apt clean


rm -rf /var/lib/apt/lists/*



sync



EOF






# =====================================
# 卸载rootfs
# =====================================


echo -e "\033[47;36m Umount rootfs.................... \033[0m"



./mount.sh -u ${TARGET_ROOTFS_DIR}



echo "Build finished"