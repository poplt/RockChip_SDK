#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"
ARCH=arm64


if [ ! $SOC ]; then
    echo "---------------------------------------------------------"
    echo "please enter soc number:"
    echo "请输入要构建CPU的序号:"
    echo "[0] Exit Menu"
    echo "[1] rk3588/rk3588s"
    echo "---------------------------------------------------------"
    read input

    case $input in
        0)  exit ;;
        1)  SOC=rk3588 ;;
        *)  echo 'input soc number error, exit !'
            exit;;
    esac
    echo -e "\033[47;36m set SOC=$SOC...... start building rootfs \033[0m"
fi


if [ ! $TARGET ]; then
    echo "---------------------------------------------------------"
    echo "please enter TARGET version number:"
    echo "请输入要构建的根文件系统版本:"
    echo "高版本文件系统默认只有全安装:"
    echo "[0] Exit Menu"
    echo "[1] gnome-full"
    echo "---------------------------------------------------------"
    read input

    case $input in
        0)  exit ;;
        1) TARGET=gnome-full ;;
        *)  echo -e "\033[47;36m input TARGET version number error, exit ! \033[0m"
            exit;;
    esac
    echo -e "\033[47;36m set TARGET=$TARGET...... \033[0m"
fi


install_packages() {
    case $SOC in
        rk3576)
        MALI=bifrost-g52-g13p0
        MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        ISP=rkaiq_rk3576
        ;;
        rk3588|rk3588s)
        # MALI=valhall-g610-g24p0
        # MALI_PKG=libmali-*$MALI*-x11-wayland-gbm*
        echo -e "\033[47;36m 默认选择开源GPU驱动跳过MALI \033[0m"
        ISP=rkaiq_rk3588
        MIRROR=carp-rk3588
        ;;
    esac
}

echo -e "\033[47;36m Building for $ARCH \033[0m"

if [ ! $VERSION ]; then
    VERSION="release"
fi

echo -e "\033[47;36m Building for $VERSION \033[0m"

if [ ! -e ubuntu-base-"$TARGET"-$ARCH-*.tar.gz ]; then
    echo "\033[41;36m 没有基础 base 请运行 mk-base-ubuntu.sh first \033[0m"
    exit -1
fi

finish() {
    sudo umount $TARGET_ROOTFS_DIR/dev
    exit -1
}
trap finish ERR

echo -e "\033[47;36m 开始提取基础镜像 \033[0m"
sudo rm -rf $TARGET_ROOTFS_DIR
#解压基础base开始
sudo tar -xpf ubuntu-base-$TARGET-$ARCH-*.tar.gz

# packages folder                         # 注释：说明下面操作与 packages 目录相关
sudo mkdir -p $TARGET_ROOTFS_DIR/packages  # 创建目标目录
sudo cp -rpf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages  # 复制软件包

#GPU/CAMERA packages folder
install_packages
sudo mkdir -p $TARGET_ROOTFS_DIR/packages/install_packages
#使用开源gpu驱动注释掉此处
# sudo cp -rpfv packages/$ARCH/libmali/$MALI_PKG.deb $TARGET_ROOTFS_DIR/packages/install_packages
#复制摄像头isp驱动包到目标根文件系统中
sudo cp -rpfv packages/$ARCH/${ISP:0:5}/camera_engine_$ISP*.deb $TARGET_ROOTFS_DIR/packages/install_packages

#linux kernel deb
if [ -e ../linux-headers* ]; then
    Image_Deb=$(basename ../linux-headers*)
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo touch $TARGET_ROOTFS_DIR/boot/build-host
    sudo cp -vrpf ../${Image_Deb} $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo cp -vrpf ../${Image_Deb/headers/image} $TARGET_ROOTFS_DIR/boot/kerneldeb
fi

#复制插件包
# overlay folder
sudo cp -rpf overlay/* $TARGET_ROOTFS_DIR/
echo -e "\033[47;36m 开始复制插件包 \033[0m"

# overlay-firmware folder
sudo cp -rpf overlay-firmware/* $TARGET_ROOTFS_DIR/
echo -e "\033[47;36m 开始复制固件包 \033[0m"

# overlay-debug folder
# adb, video, camera  test file
if [ "$VERSION" == "debug" ]; then
    sudo cp -rpf overlay-debug/* $TARGET_ROOTFS_DIR/
    echo -e "\033[47;36m 开始复制调试包 \033[0m"
fi

## hack the serial
sudo cp -f overlay/usr/lib/systemd/system/serial-getty@.service $TARGET_ROOTFS_DIR/lib/systemd/system/serial-getty@.service
echo -e "\033[47;36m 复制qemu-aarch64-static到文件系统 \033[0m"
sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
echo -e "\033[47;36m 挂载文件系统 \033[0m"
./ch-mount.sh -m $TARGET_ROOTFS_DIR

echo -e "\033[47;36m 获取用户ID \033[0m"
ID=$(stat --format %u $TARGET_ROOTFS_DIR)
echo -e "\033[47;36m 执行chroot进入环境 \033[0m"
cat << EOF | sudo chroot $TARGET_ROOTFS_DIR


#以避免权限问题
# Fixup owners
if [ "$ID" -ne 0 ]; then
    find / -user $ID -exec chown -h 0:0 {} \;
fi
for u in \$(ls /home/); do
    chown -h -R \$u:\$u /home/\$u
done

#添加野火源如fire-config等
# Add embedfire packages source
mkdir -p /etc/apt/keyrings
curl -fsSL https://Embedfire.github.io/keyfile | gpg --dearmor -o /etc/apt/keyrings/embedfire.gpg
chmod a+r /etc/apt/keyrings/embedfire.gpg
echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/embedfire.gpg] https://cloud.embedfire.com/mirrors/ebf-debian carp-lbc main" | tee /etc/apt/sources.list.d/embedfire-lbc.list > /dev/null
if [ $MIRROR ]; then
    echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/embedfire.gpg] https://cloud.embedfire.com/mirrors/ebf-debian $MIRROR main" | tee /etc/apt/sources.list.d/embedfire-$MIRROR.list > /dev/null
fi

export LC_ALL=C.UTF-8

echo -e "\033[47;36m ------ 准备开始更新---------- \033[0m"
apt-get update
apt-get upgrade -y

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
chmod +x /etc/rc.local

export DEBIAN_FRONTEND=noninteractive
export APT_INSTALL="apt-get install -fy --allow-downgrades"

echo -e "\033[47;36m ---------- LubanCat -------- \033[0m"
apt purge initramfs-tools -y

\${APT_INSTALL} gdisk fire-config-gui
#Desktop background picture
# ln -sf /usr/share/xfce4/backdrops/lubancat-wallpaper.png /usr/share/backgrounds/warty-final-ubuntu.png

# echo -e "\033[47;36m ---------- 安装rk相关的支持包 -------- \033[0m"
# \${APT_INSTALL} /packages/install_packages/*.deb
echo -e "\033[47;36m ---------- 安装内核包 -------- \033[0m"
\${APT_INSTALL} /boot/kerneldeb/* || true


echo -e "\033[47;36m ----- 安装电源管理器 ----- \033[0m"
\${APT_INSTALL} pm-utils triggerhappy bsdmainutils
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service
sed -i "s/#HandlePowerKey=.*/HandlePowerKey=ignore/" /etc/systemd/logind.conf

# echo -e "\033[47;36m ----------- RGA  ----------- \033[0m"
# \${APT_INSTALL} /packages/rga2/*.deb


# echo -e "\033[47;36m ------ 安装 Video---------- \033[0m"
# \${APT_INSTALL} gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-ugly gstreamer1.0-tools gstreamer1.0-alsa \
# gstreamer1.0-plugins-base-apps
# \${APT_INSTALL} /packages/mpp/*
# \${APT_INSTALL} /packages/gst-rkmpp/*.deb
# \${APT_INSTALL} /packages/gstreamer/*.deb

echo -e "\033[47;36m ----- Install Camera ------- \033[0m"
\${APT_INSTALL} cheese v4l-utils

echo -e "\033[47;36m ----- Wayland/Weston ------- \033[0m"
#暂且先跳过
#\${APT_INSTALL} libseat-dev
#\${APT_INSTALL} /packages/wayland/*.deb

# echo -e "\033[47;36m ------ update chromium ----- \033[0m"
# \${APT_INSTALL} /packages/chromium/*.deb

echo -e "\033[47;36m ------ Install glmark2 ------ \033[0m"
\${APT_INSTALL} glmark2-es2

# if [ -e "/usr/lib/aarch64-linux-gnu" ] ; then
# echo -e "\033[47;36m ------- 复制 rknpu2 --------- \033[0m"
# mv /packages/rknpu2/rknpu2.tar  /
# fi

# echo -e "\033[47;36m ----- 安装 rktoolkit ----- \033[0m"
# \${APT_INSTALL} /packages/rktoolkit/*.deb

echo -e "\033[47;36m ------ Install scratch ------- \033[0m"
\${APT_INSTALL} /packages/embedfire/scratch_*.deb

echo -e "\033[47;36m ------- Custom Script ------- \033[0m"
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl disable hostapd
rm /lib/systemd/system/wpa_supplicant@.service

rm -rf /home/$(whoami)
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
rm -rf /packages/
rm -rf /boot/*
rm -rf /root/.bash_history


EOF

./ch-mount.sh -u $TARGET_ROOTFS_DIR

source ./mk-image.sh 
