# CIX-P1-ACPI Ubuntu img适配方法

## 一. 制作启动镜像

## 前言

    本文档适用于Ubuntu22.04、Ubuntu24.04、Ubuntu25.05版本在此芯P1芯片上的适配，以Radxa O6和Cix EVB板子为例编写的文档，其它开发板也可以借鉴此文档，核心的区别在于boot.img和内核的deb包不同。

### 1.1 Ubuntu img介绍

    一些ubuntu版本采用了一些比较老的内核（6.12之前），iso镜像无法在CIX P1上安装，这个时候我们需要下载树莓派的镜像，替换成CIX的内核再放到CIX P1上启动。在[Index of /ubuntu/releases](https://cdimage.ubuntu.com/ubuntu/releases/) 网页选择所需版本的Ubuntu preinstalled desktop img镜像文件，例如: https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.3-preinstalled-desktop-arm64+raspi.img.xz 。

### 1.2 制作启动盘

    以下操作都是在x86主机上进行，推荐使用ubuntu24.04系统。 

#### 1.2.1 所需材料

**注意：boot.img和kernel通过25Q3 Release中获取。**

1. Ubuntu img文件
2. 准备一个nvme和nvme读卡器
3. 准备boot.img  
4. 准备kernel相关的deb包：
   linux-libc-dev_6.6.xxxxx_arm64.deb
   linux-image-6.6.xxx_arm64.deb
   linux-headers-6.6xxx_arm64.deb
   cix-env_xxx_arm64.deb
   cix-firmware_xxx_arm64.deb

#### 1.2.2 dd镜像

将nvme接读卡器插入下x86 linux主机，使用命令烧写镜像

```
sudo dd if=ubuntu-24.04.xxx-preinstalled-desktop-arm64+raspi.img of=/dev/sdxxx bs=10M status=progress 
```

**注意：刷完之后重新插拔一下烧录器，以便系统重新识别分区和文件系统  1.2.3    更换kernel**

1. 替换Image和grub 

```

mkdir -p /mnt/boot
mkdir -p /mnt/1
mount /dev/sda1 /mnt/1        //sda1是EFI分区
mount boot.img /mnt/boot
rm -rf /mnt/1/* 
cp -rf /mnt/boot/* /mnt/1
```

2. 修改grub启动参数
-  修改/mnt/1/GRUB/GRUB.CFG，将其中的uuid  改成/dev/nvme0n1p2

- 修改默认启动项，Radxa O6修改默认启动项为31，CIX EVB板则是1。

- 如果所选启动选存在initrd启动，则删除
  **修改前：**

```
cat /mnt/1/GRUB/GRUB.CFG
set debug=loader,mm
set term=vt100
set default=0        //Radxa修改默认启动项为31，P1 EVB板则是1
set timeout=2

......

menuentry '1 Cix Sky1 on EVB (ACPI)' {
    linux /Image \
        console=ttyAMA2,115200 \
        efi=noruntime \
        earlycon=pl011,0x040d0000 \
        arm-smmu-v3.disable_bypass=0 \
        cma=640M \
        acpi=force splash \
        loglevel=4 \
        pcie_aspm=off \
        resume=PARTUUID=4c3b24d6-6bf4-4073-91f8-0fc9313947a6 noresume root=PARTUUID=a7cd7254-f1f8-48f6-8617-efe92d1154cb rootwait rw    //uuid 改成/dev/nvme0n1p2
    initrd /initrd.img-6.6.89-cix-build-generic        //initrd这行需删除
}

......
```

 **以EVB板为例，修改后：**

```
at /mnt/1/GRUB/GRUB.CFG
set debug=loader,mm
set term=vt100
set default=1
set timeout=2

......

menuentry '1 Cix Sky1 on EVB (ACPI)' {
    linux /Image \
        console=ttyAMA2,115200 \
        efi=noruntime \
        earlycon=pl011,0x040d0000 \
        arm-smmu-v3.disable_bypass=0 \
        cma=640M \
        acpi=force splash \
        loglevel=4 \
        pcie_aspm=off \
        resume=PARTUUID=4c3b24d6-6bf4-4073-91f8-0fc9313947a6 noresume root=/dev/nvme0n1p2
}

......
```

 

3. 安装 cix kernel包

```
mkdir -p /mnt/2
mount /dev/sda2 /mnt/2          //sda2是根分区
```

    将linux-libc-dev_6.6.xxxxx_arm64.deb、linux-image-6.6.xxx_arm64.deb、linux-headers-6.6.xxx_arm64.deb、cix-env_xxx_arm64.deb、cix-firmware_xxx_arm64.deb这五个包拷贝到/mnt/2

```
chroot /mnt/2                //进入rootfs chroot环境
dpkg -i linux-*.deb                     //安装rootfs中的ko
dpkg –i cix-firmware_xxx_arm64.deb    
dpkg –i --force-overwrite cix-env_xxx_arm64.deb
```

4. 修改系统服务
   **注意保持chroot环境**

```
systemctl disable oem-config.service  
systemctl disable unattended-upgrades
systemctl disable cloud-init-local cloud-init cloud-config cloud-final 
systemctl set-default graphical.target
useradd -m -G sudo,video cix
passwd cix    //随后输入cix用户的密码
exit  //退出chroot环境  
umount /mnt/boot
umount /mnt/1
umount /mnt/2
```

5. 根分区扩容（**注意：必要操作，否则系统无法启动**）

```
parted /dev/sda   //进入根据自身使用需求扩容10%~100%
e2fsck -f /dev/sda2
resize2fs /dev/sda2  
```

#### 1.2.4    启动系统

将nvme放到Radxa O6机器上开机后能够自动boot到Ubuntu系统。 



## 第2章 安装deb包使能硬件

**注意：ubuntu22.04版本因gcc版本小于12不支持 trivial-auto-var-init 编译选项，所以dkms编译需要修改内核头文件中的Makefile，修改方法：删除/usr/src/linux-headers-6.6.89-cix-build-generic/Makefile 中“KBUILD_CFLAGS   += -ftrivial-auto-var-init=zero ”这一行**

### 2.1 安装GPU

    准备相关包： cix-go-xxx.tar.gz

```
sudo su  
rm -rf /bin/sh 
ln -sf /bin/bash /bin/sh  

apt update 
apt install libxcb-dri2-0 
apt install dkms 

tar -xvf cix-go-xxx.tar.gz 
cd cix-go 
./install.sh --dkms   

reboot
```



### 2.2 安装NPU

准备相关包： 

    cix-npu-driver_xxx_arm64.deb

    cix-noe-umd_xxx_arm64.deb

```
sudo dpkg -i *.deb 

sudo apt update sudo
sudo apt install python3-pip
sudo apt install dkms 

sudo dkms add -m  aipu -v 5.11.0  
sudo dkms build -m aipu -v 5.11.0 
sudo dkms install -m aipu -v 5.11.0 --force
sudo reboot 
```



### 2.3  安装VPU

    准备相关包： 

        cix-vpu-test_xxx_arm64.deb

        cix-vpu-driver_xxx_arm64.deb

        cix-vpu-driver-dkms_xxx_arm64.deb

```
sudo dpkg -i *.deb
sudo apt update
sudo apt install dkms

sudo dkms add -m cix-vpu-driver -v 1.0.0
sudo dkms build -m cix-vpu-driver -v 1.0.0
sudo dkms install -m cix-vpu-driver -v 1.0.0 --force
sudo reboot 2.4    
```



### 2.4 Ffmpeg&gstreamer硬解

注意：只适用于ubuntu24.04

准备相关包：

1. Ffmpeg
   libavcodec60_6.1.1-xxx_arm64.deb

2. Gstreamer
   gir1.2-gst-plugins-base-1.0_1.24.2-xxx_arm64.deb
   gstreamer1.0-gl_1.24.2-xxx_arm64.deb
   gstreamer1.0-gtk3_1.24.2-xxx_arm64.deb
   gstreamer1.0-plugins-base-apps_1.24.2-xxx_arm64.deb
   gstreamer1.0-plugins-base_1.24.2-xxx_arm64.deb
   gstreamer1.0-plugins-good_1.24.2-xxx_arm64.deb
   gstreamer1.0-pulseaudio_1.24.2-xxx_arm64.deb
   libgstreamer-plugins-base1.0-0_1.24.2-xxx_arm64.deb
   libgstreamer-plugins-good1.0-0_1.24.2-xxx _arm64.deb
   
   ```
   sudo apt update
   sudo apt install ffmpeg   mpv
   sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav   gstreamer1.0-tools
   dpkg –i *.deb
   //mpv 使用
   mpv --hwdec=auto ‘filename’
   ```

### 2.5    安装Alsa配置文件

    准备相关包：

        cix-alsa-conf_xxx_arm64.deb

```
sudo dpkg -i cix-alsa-conf_xxx_arm64.deb
sudo reboot
```

### 2.6    安装wifi&bt驱动

    准备相关包：

        cix-wlan_xxx_arm64.deb

        cix-bt-driver_xxx_arm64.deb

```
sudo dpkg –i cix-wlan_xxx_arm64.deb
sudo dpkg –i cix-bt-driver_xxx_arm64.deb
sudo depmod -a
sudo reboot
```

**•    设置-网络中显示双网卡问题解决方法：**

```
sudo sed -i 's/NAME=\"$env{ID_NET_NAME}\"/NAME=\"$env{ID_NET_SLOT}\"/' /usr/lib/udev/rules.d/80-net-setup-link.rules
sudo sed -i "/ACTION!=\"add|change|move\",/aENV{INTERFACE}==\"p2p\",  ENV{NM_UNMANAGED}=\"1\"" /usr/lib/udev/rules.d/85-nm-unmanaged.rules
```

## 第三章 FAQ

### 1. Firefox启动失败

**备注：Ubuntu22和Ubuntu24环境需要配置snap环境**

1.1 下载指定版本的Snapd

```
 sudo snap download snapd --revision=24724
```

1.2 安装并锁定版本

```
 sudo snap ack snapd_24724.assert
 sudo snap install snapd_24724.snap
 sudo snap refresh --hold snapd
```

1.3 修改内核patch

```
CONFIG_BPF_SYSCALL=y

CONFIG_SQUASHFS_XZ=y
CONFIG_SQUASHFS_LZ4=y
CONFIG_SQUASHFS_LZO=y
CONFIG_SQUASHFS_ZSTD=y
```


