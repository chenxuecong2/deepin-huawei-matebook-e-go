# 介绍

树莓派运行 deepin 系统。

# 下载构建仓库

```bash
git clone --depth=1 https://github.com/deepin-community/deepin-raspberrypi.git
```

# 构建镜像

基础镜像，安装的软件包记录在在 profiles/packages.txt，可以根据需要修改。另外会安装树莓派官方提供的驱动和内核包。

项目下运行以下命令。

```bash
./build.sh
```

包含桌面环境的镜像，在基础镜像上天添加

- deepin-desktop-environment-base
- deepin-desktop-environment-cli
- deepin-desktop-environment-core
- deepin-desktop-environment-extras
- uos-ai （UOS AI）
- firefox
- treeland （deepin 系统的 wayalnd 窗管）
- ddm （ treeland 窗管配套的显示管器）

项目下运行以下命令。

```bash
./build.sh desktop
```

# 启动

## 尝试使用 qemu 启动

下面使用的内核和设备树是我编译的，也可以直接拷贝 firmware 中的 kernel.img 和 bcm2710-rpi-3-b.dtb

```bash
qemu-system-aarch64 -machine type=raspi3b \
        --cpu arm1176 \
        -m 1G  \
        -dtb ./firmware/bcm2710-rpi-3-b.dtb \
        -kernel ./firmware/kernel8.img \
        -drive id=hd-root,format=raw,file=deepin-raspberrypi.img \
        -append "rw earlyprintk loglevel=8 console=ttyAMA0,115200 dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootwait panic=1 dwc_otg.fiq_fsm_enable=0" \
        -serial stdio \
        -netdev user,id=net0,hostfwd=tcp::8022-:22 -device usb-net,netdev=net0 \
        -usb -device usb-kbd -device usb-tablet
```

## 从 SD 卡启动

树莓派官方下载烧录工具，https://www.raspberrypi.com/software。

根据开发板选择对应的选项，再使用生成的镜像进行烧录。

# 安装桌面环境

```bash
sudo apt update && sudo apt upgrade
```

```bash
sudo apt install deepin-desktop-environment-{base,cli,core,extras}

# 如果需要使用 treeland 窗管
sudo apt install treeland ddm
# 禁用 lightdm 自启动，允许 ddm 自启动
sudo systemctl disable lightdm && sudo systemctl enable ddm
# 停止 lightdm，启动 ddm
sudo systemctl stop lightdm && sudo systemctl enable ddm

```

安装完重启树莓派。

# 参考

[QEMU仿真树莓派1和3B-保姆级教程](https://zhuanlan.zhihu.com/p/452590356?utm_id=0)

[raspberrypi document0ation](https://www.raspberrypi.com/documentation/computers/linux_kernel.html?spm=5176.28103460.0.0.247d3f99dF96wJ&file=updating.md)
