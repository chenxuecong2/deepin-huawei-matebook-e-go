#!/bin/bash

set -xe
# 不进行交互安装
export DEBIAN_FRONTEND=noninteractive
BUILD_TYPE="$1"
ROOTFS="rootfs"
TARGET_DEVICE=gaokun
ARCH="arm64"
DISKIMG="deepin-$TARGET_DEVICE.img"
IMAGE_SIZE=$( [ "$BUILD_TYPE" == "desktop" ] && echo 12288 || echo 4096 )
readarray -t REPOS < ./profiles/sources.list
PACKAGES=$(cat ./profiles/packages.txt | grep -v "^-" | xargs | sed -e 's/ /,/g')

function run_command_in_chroot()
{
    rootfs="$1"
    command="$2"
    sudo chroot "$rootfs" /usr/bin/env bash -e -o pipefail -c "export DEBIAN_FRONTEND=noninteractive && $command"
}

# 设置 chroot 环境
function setup_chroot_environment() {
    local TMP="$1" # 假设 $TMP 是目标chroot环境的根目录

    # 挂载 /dev 目录，允许在 chroot 环境中访问设备文件
    sudo mount --bind /dev "$TMP/dev"

    # 挂载 proc 文件系统提供了一个接口来访问内核状态信息，如进程列表等
    sudo mount -t proc chproc "$TMP/proc"

    # 挂载 sysfs 提供了访问内核模块、硬件设备和其他系统级别的信息
    sudo mount -t sysfs chsys "$TMP/sys"

    # 挂载临时文件系统
    sudo mount -t tmpfs -o "size=99%" tmpfs "$TMP/tmp"
    sudo mount -t tmpfs -o "size=99%" tmpfs "$TMP/var/tmp"

    # 挂载 devpts 文件系统负责为伪终端提供设备节点，支持文本用户界面和shell会话
    sudo mount -t devpts devpts "$TMP/dev/pts"
}

sudo apt update -y
case $(uname -m) in
x86_64)
    # 在 x86 上构建，需要利用 qemu 并开启 binfmt 异架构支持
    sudo apt install aptitude
    sudo aptitude install -y qemu-user-static binfmt-support mmdebstrap arch-test usrmerge usr-is-merged qemu-system-misc systemd-container fdisk dosfstools 
    sudo systemctl restart systemd-binfmt
    ;;
aarch64)
    # arm64 上构建
    sudo apt-get install -y mmdebstrap usrmerge usr-is-merged systemd-container fdisk dosfstools
    ;;
esac

if [ ! -d "$ROOTFS" ]; then
    mkdir -p $ROOTFS
    # 创建根文件系统
    sudo mmdebstrap \
        --hook-dir=/usr/share/mmdebstrap/hooks/merged-usr \
        --skip=check/empty \
        --include=$PACKAGES \
        --components="main,commercial,community" \
        --architectures=${ARCH} \
        beige \
        $ROOTFS \
        "${REPOS[@]}"

    if [[ "$BUILD_TYPE" == "desktop" ]] && [[ "$(uname -m)" == "aarch64" ]];
    then
        setup_chroot_environment $ROOTFS
        # 安装桌面环境，添加火狐浏览器，另外安装 treeland 窗管
        run_command_in_chroot $ROOTFS "apt update -y && apt install -y \
            deepin-desktop-environment-core \
            deepin-desktop-environment-base \
            deepin-desktop-environment-cli \
            deepin-desktop-environment-extras \
            firefox \
            ddm \
            treeland"
        # 默认启用的 lightdm 窗管，这里禁用 lightdm，使用 ddm。
        run_command_in_chroot $ROOTFS "
        systemctl disable lightdm
        systemctl enable ddm"
        umount -l $ROOTFS
    else
        # 需要使用树莓派构建带桌面的镜像，dkms 模块依赖内核，使用 qemu 无法正确编译。
        echo "Need to build the image using Raspberry Pi"
    fi
fi


sudo echo "deepin-$TARGET_DEVICE" | sudo tee $ROOTFS/etc/hostname > /dev/null

# 创建磁盘文件
dd if=/dev/zero of=$DISKIMG bs=1M count=$IMAGE_SIZE
sudo fdisk deepin-gaokun.img << EOF
n
p
1

+300M
t
c
n
p
2


w
EOF

# 格式化
LOOP=$(sudo losetup -Pf --show $DISKIMG)
sudo mkfs.fat -F32 "${LOOP}p1"
sudo dosfslabel "${LOOP}p1" efi
sudo mkfs.ext4 "${LOOP}p2" # 根分区 (/)
sudo e2label "${LOOP}p2" rootfs

TMP=$(mktemp -d)
sudo mount "${LOOP}p2" $TMP
sudo cp -a $ROOTFS/* $TMP

sudo mkdir $TMP/boot/efi
sudo mount "${LOOP}p1" $TMP/boot/efi

sudo cp -r firmware/* $TMP/boot/efi

setup_chroot_environment $TMP

sudo rm -f $TMP/etc/resolv.conf
sudo cp /etc/resolv.conf $TMP/etc/resolv.conf

# deepin 源里没 libfmt9，已经到 libfmt10 了，从 debian 下载 deb 包
curl -L http://ftp.cn.debian.org/debian/pool/main/f/fmtlib/libfmt9_9.1.0+ds1-2_arm64.deb -o $TMP/tmp/libfmt9.deb
curl -L http://ftp.cn.debian.org/debian/pool/main/d/device-tree-compiler/libfdt1_1.6.1-4+b1_arm64.deb -o $TMP/tmp/libfdt1.deb
run_command_in_chroot $TMP "apt update -y && apt install -y \
    /tmp/libfmt9.deb \
    /tmp/libfdt1.deb"

# 安装内核
sudo cp debs/**.deb $ROOTFS

run_command_in_chroot $TMP "dpkg -i --force-overwrite /*.deb \"

sudo cp $ROOTFS/boot/initrd*6.14* $TMP/boot/efi/initrd.img

# 编辑分区表
sudo tee $TMP/etc/fstab << EOF
proc          /proc           proc    defaults          0       0
LABEL=bootfs  /boot/efi  vfat    defaults          0       2
LABEL=rootfs  /               ext4    defaults,rw,errors=remount-ro,x-systemd.growfs  0       1
EOF

run_command_in_chroot $TMP "sed -i -E 's/#[[:space:]]?(en_US.UTF-8[[:space:]]+UTF-8)/\1/g' /etc/locale.gen
sed -i -E 's/#[[:space:]]?(zh_CN.UTF-8[[:space:]]+UTF-8)/\1/g' /etc/locale.gen
"

run_command_in_chroot $TMP "useradd -m -g users deepin && usermod -a -G sudo deepin
chsh -s /bin/bash deepin
echo deepin:deepin | chpasswd"

# 删除 root 的密码
sudo sed -i 's/^root:[^:]*:/root::/' $TMP/etc/shadow

run_command_in_chroot $TMP "locale-gen"

# 清理缓存
run_command_in_chroot $TMP "apt clean
rm -rf /var/cache/apt/archives/*
rm /boot/*
rm /*.deb
"
sudo umount -l $TMP

# 会强制检查指定的文件系统
sudo e2fsck -f "${LOOP}p2"
# 收缩文件系统，使其刚好容纳现有的数据
sudo resize2fs -M "${LOOP}p2"

sudo losetup -D $LOOP
sudo rm -rf $TMP
