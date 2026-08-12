#!/bin/bash -e


TARGET_ROOTFS_DIR=./binary


if [ $RK_ROOTFS_IMAGE ]; then
    ROOTFSIMAGE=$RK_ROOTFS_IMAGE
else
    ROOTFSIMAGE=openkylin-$SOC-$TARGET-rootfs.img
fi


echo Making rootfs!


if [ -e ${ROOTFSIMAGE} ]; then
    rm -f ${ROOTFSIMAGE}
fi



# 添加构建信息
if [ -x ./add-build-info.sh ]; then
    sudo ./add-build-info.sh ${TARGET_ROOTFS_DIR}
fi



# 计算镜像大小
IMAGE_SIZE_MB=$(( \
$(sudo du --apparent-size -sm ${TARGET_ROOTFS_DIR} | cut -f1) \
+ $(sudo find ${TARGET_ROOTFS_DIR} | wc -l) * 4 / 1024 \
+ 64 ))



# 增加10%
IMAGE_SIZE_MB=$((IMAGE_SIZE_MB * 110 / 100))



echo "Image size:"
echo "${IMAGE_SIZE_MB} MB"



sudo mkfs.ext4 \
-d ${TARGET_ROOTFS_DIR} \
${ROOTFSIMAGE} \
${IMAGE_SIZE_MB}M



echo "Rootfs Image:"
echo ${ROOTFSIMAGE}