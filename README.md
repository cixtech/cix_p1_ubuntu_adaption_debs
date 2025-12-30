# CIX-P1-ACPI Ubuntu Image Adaptation Method

## Chapter  I. Creating a Boot Image

### Preface

    This document is applicable for adapting Ubuntu 22.04, Ubuntu 24.04, and Ubuntu 25.04 versions on the CIX P1. It is written using the Radxa O6 board as an example. Other development boards featuring the CIX P1 can also refer to this document. Note that different development boards require different kernels for booting, relevant kernel source code can be obtained from the respective development board vendor.

### 1.1 Ubuntu Image Introduction

    Some Ubuntu versions use relatively older kernels (prior to 6.12), and their ISO images cannot be installed directly on the CIX P1 platform. In such cases, we need to download a Raspberry Pi image, replace the kernel-related files in the boot partition with the Radxa kernel, and then use it to boot on the Radxa O6 board. On the [Index of /ubuntu/releases](https://cdimage.ubuntu.com/ubuntu/releases/) webpage, select the desired version of the Ubuntu preinstalled desktop image file, for example: https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.3-preinstalled-desktop-arm64+raspi.img.xz.

### 1.2 Creating the Boot Disk

    The following operations are performed on an x86 host machine; Ubuntu 24.04 system is recommended.

#### 1.2.1 Required Materials

1. Ubuntu preinstalled desktop image file ([Index of /ubuntu/releases](https://cdimage.ubuntu.com/ubuntu/releases/))

2. Prepare an NVMe SSD and an NVMe card reader

3. Prepare the kernel source code (**Note: Obtain the kernel source code from the original vendor**).

4. Prepare the kernel Image file and deb packages (**Outputs from kernel source compilation**): 
   
   * `Image`
   * `linux-libc-dev_6.6.xxxxx_arm64.deb`
   * `linux-image-6.6.xxx_arm64.deb`
   * `linux-headers-6.6xxx_arm64.deb`

5. Prepare the GRUB directory files (**Provided by this GitHub repository**)

6. Prepare the EFI directory files (**Provided by this GitHub repository**)

7. Other files (**Provided by this GitHub repository**):
   
   * `cix-env_xxx_arm64.deb`
   * `cix-firmware_xxx_arm64.deb`

#### 1.2.2 DD the Image

    Connect the NVMe SSD to the x86 Linux host via the card reader, and use the following command to write the image(**Note: sdxxx should be modified according to the actual NVMe device node, which can be checked using lsblk, e.g., /dev/sda, /dev/sdb, etc.**):

```
sudo dd if=ubuntu-24.04.xxx-preinstalled-desktop-arm64+raspi.img of=/dev/sdxxx bs=10M status=progress
```

**Note: After flashing, reconnect the card reader to allow the system to re-recognize the partitions and filesystems.**

#### 1.2.3  Replacing the Kernel

**Note: The kernel replacement method is demonstrated using Radxa O6 as an example. For other development boards, obtain the kernel code from the respective board vendor.**

1. Add relevant kernel configs
   * After obtaining the source code, Modify the `linux/arch/arm64/configs/cix.config` file:

```
   CONFIG_BPF_SYSCALL=y

   CONFIG_SQUASHFS_XZ=y
   CONFIG_SQUASHFS_LZ4=y
   CONFIG_SQUASHFS_LZO=y
   CONFIG_SQUASHFS_ZSTD=y
```

        

2. Obtaining Source Code and Compiling Kernel for Radxa O6(**choose one method**):
   
   * Obtain and compile kernel code separately
     
     - Source code location: [radxa-pkg/linux-sky1: Radxa Linux image for sky1 release](https://github.com/radxa-pkg/linux-sky1)  (**Note: Refer to README for download and compilation instructions**)
     
     - Output locations:
       
       1. `./arch/arm64/boot/Image`
       2. `../linux-libc-dev_6.6.xxxxx_arm64.deb`
       3. `../linux-image-6.6.xxx_arm64.deb`
       4. `../linux-headers-6.6xxx_arm64.deb`
   
   * Obtain and compile complete O6 Cix P1 source code
     
     * Source code: [Obtain the Source Code | Radxa Docs](https://docs.radxa.com/en/orion/o6/cix-sdk/get-source) 
     * Compilation method: [Software Compilation | Radxa Docs](https://docs.radxa.com/en/orion/o6/cix-sdk/build)  (**Note: To compile only the kernel, prepare the build environment and use the build kernel command**) 
     * Output locations:
       1. `./output/cix_evb/Image`
       2. `./output/cix_evb/debs/linux-libc-dev_6.6.xxxxx_arm64.deb`
       3. `./output/cix_evb/debs/linux-image-6.6.xxx_arm64.deb`
       4. `./output/cix_evb/debs/linux-headers-6.6xxx_arm64.deb`

3. Compile the kernel using the build environment provided by the original vendor to generate the required outputs:    

            `Image`

            `linux-libc-dev_6.6.xxx_arm64.deb`

            `linux-image-6.6.xxx_arm64.deb`

            `linux-headers-6.6xxx_arm64.deb`

4. Replace the Image file and GRUB directory

```
mkdir -p /mnt/bootfs
mount /dev/sda1 /mnt/bootfs       // sda1 is the EFI partition
rm -rf /mnt/bootfs/*
cp -f Image /mnt/bootfs
cp -rf GRUB /mnt/bootfs
cp -rf EFI /mnt/bootfs
```

5. Install kernel packages

```
mkdir -p /mnt/rootfs
mount /dev/sda2 /mnt/rootfs         // sda2 is the root partition
```

    Copy the following five packages to `/mnt/rootfs`: `linux-libc-dev_6.6.xxxxx_arm64.deb`, `linux-image-6.6.xxx_arm64.deb`, `linux-headers-6.6.xxx_arm64.deb`, `cix-env_xxx_arm64.deb`, `cix-firmware_xxx_arm64.deb`

```
chroot /mnt/rootfs                // Enter the rootfs chroot environment
dpkg -i linux-*.deb               // Install the kernel packages in rootfs. Note: Ignore any kernel installation errors.
dpkg -i cix-firmware_xxx_arm64.deb    
dpkg -i --force-overwrite cix-env_xxx_arm64.deb
```

6. Modify system services
   **Note: Remain in the chroot environment**

```
systemctl disable oem-config.service  
systemctl disable unattended-upgrades
systemctl disable cloud-init-local cloud-init cloud-config cloud-final NetworkManager-wait-online
systemctl set-default graphical.target
useradd -m -G sudo,video cix
passwd cix    // Then enter the password for the 'cix' user
exit  // Exit chroot environment

umount /mnt/bootfs
umount /mnt/rootfs
```

7. Root Partition Resizing
   **Note: Essential step, otherwise the system may fail to boot, resize according to your needs (10%~100%)**

```
parted /dev/sda   // Within parted, use `resizepart 2 ...` and `quit`
e2fsck -f /dev/sda2
resize2fs /dev/sda2  
```

#### 1.2.4 Booting the System

    Place the NVMe SSD into the Radxa O6 machine and power on; it should automatically boot into the Ubuntu system.



## Chapter 2. Enable Hardware

**Note 1: Ubuntu 22.04, due to its GCC version being less than 12, does not support the `-ftrivial-auto-var-init` compilation option. Therefore, DKMS compilation requires modifying the Makefile in the kernel headers. Modification method: Delete the line `KBUILD_CFLAGS += -ftrivial-auto-var-init=zero` in `/usr/src/linux-headers-6.6.89-cix-build-generic/Makefile`.**

**Note 2: The relevant packages mentioned below are obtained from this GitHub repository.**

### 2.1 Quick Installation

- After copying the `debs` directory to the Ubuntu system, navigate to the `debs` directory and execute the following command:

```
sudo ./cix-install.sh
```

**Note: After executing this command, the remaining steps in Chapter 2 do not need to be performed.**



### 2.2 GPU Installation

Prepare the relevant package: 

- `cix-go-xxx.tar.gz`

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



### 2.3 NPU Installation

Prepare the relevant packages:

* `cix-npu-driver_xxx_arm64.deb`

* `cix-noe-umd_xxx_arm64.deb`

```
sudo apt update
sudo apt install python3-pip
sudo dpkg -i *.deb 

sudo apt install dkms 
sudo dkms add -m  aipu -v 5.11.0  
sudo dkms build -m aipu -v 5.11.0 
sudo dkms install -m aipu -v 5.11.0 --force
sudo reboot 
```



### 2.4  VPU Installation

Prepare the relevant packages:

* `cix-vpu-test_xxx_arm64.deb`

* `cix-vpu-driver-dkms_xxx_arm64.deb`

```
sudo apt update 
sudo apt install dkms 
sudo dpkg -i *.deb 

sudo reboot 
```



### 2.5 Ffmpeg & Gstreamer Hardware Decoding

**Note: Only applicable to Ubuntu 24.04**

Prepare the relevant packages:

1. Ffmpeg(6.1.1 for ubuntu24.04，7.1.1 for ubuntu25.04)
   
   * `ffmpeg-xxx_arm64.deb`
   * `libavcodec-xxx_arm64.deb``
   * `libavformat-xxx_arm64.deb`
   * `libavutil-xxx_arm64.deb libavfilter-xxx_arm64.deb(Only required for Ubuntu 25.04)`
   * `libavdevice-xxx_arm64.deb(Only required for Ubuntu 25.04)`
   * `libswscale-xxx_arm64.deb(Only required for Ubuntu 25.04)`

2. Gstreamer(1.24 for ubuntu24.04，1.26 for ubuntu25.04)
   
   * `cix-gstreamer_1.2xxx.deb`

```
sudo apt update 
sudo apt install ffmpeg mpv
sudo apt install gstreamer1.0-plugins-bad gstreamer1.0-libav gstreamer1.0-tools 
dpkg –i *.deb

//mpv 使用 
mpv  --hwdec=auto ‘filename’    // ubuntu24.04 
mpv --hwdec=auto-unsafe –vo=gpu --gpu-context=wayland --gpu-dumb-mode=yes ‘filename’   // ubuntu25.04 
```



### 2.6 Alsa Configuration Files Installation

Prepare the relevant package:

* `cix-alsa-conf_xxx_arm64.deb`

```
sudo dpkg -i cix-alsa-conf_xxx_arm64.deb
sudo reboot
```



### 2.7 Installing WiFi & BT Drivers

Prepare the relevant packages:

* `cix-wlan_xxx_arm64.deb`

* `cix-bt-driver_xxx_arm64.deb`

```
sudo dpkg –i cix-wlan_xxx_arm64.deb
sudo dpkg –i cix-bt-driver_xxx_arm64.deb
sudo depmod -a
sudo reboot
```



## Chapter 3. FAQ

### 1. **System and Application Issues**

#### 1.1 Firefox Fails to Start -- Snap Environment Configuration

- Download the specified version of Snapd

```
sudo snap download snapd --revision=24724
```

- Install and lock the version

```
sudo snap ack snapd_24724.assert
sudo snap install snapd_24724.snap
sudo snap refresh --hold snapd
```

#### 1.2 Memory Leak in Clapper Playback and Snapshot

- Export the following environment variable before running 

```
export GSK_GPU_DISABLE=mipmap
```

#### 1.3 SMPlayer Fails to Open on Ubuntu 25.04

- Export the following environment variable before running

```
export QT_QPA_PLATFORM=wayland
```

#### 1.4 **Disable automatic updates to Avoid GPU malfunctions**

- Open 'Software & Update' app, select Updates tab, and change the 'Automatically check for updates' option on that page to '**Never**'.

- Additionally, you can disable automatic updates via command line.

```
sudo systemctl disable unattended-upgrades
```



## 2. Display Issues

#### 2.1 How to Handle Screen Flickering Issues

* If screen flickering occurs, it is recommended to connect the screen to the DP-1 interface (generally the Type-C port on the board closest to the USB port). After connecting, check using the command:
  
      cat /sys/class/drm/card0-DP-1/status    // If it displays 'connected', the connection is correct.

#### 2.2 Ubuntu22.04 es2gears_wayland Segmentation fault

    This is caused by an issue within the es2gears_wayland application itself, not a GPU problem.

#### 2.3 Ubuntu 22.04: vulkaninfo Error

- **Error 1**： 

```
ERROR: [Loader Message] Code 0 : loader_validate_instance_extensions: Extension VK_EXT_surface_maintenance1 not found in list of known instance extensions. ERROR at ./vulkaninfo/vulkaninfo.h:651:vkCreateInstance failed with ERROR_EXTENSION_NOT_PRESENT 
```

- This is caused by a version mismatch between the higher version of the Mali Vulkan driver and the Vulkan loader that comes with Ubuntu 22.04. It can be resolved by replacing the content of `/etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json` with the following:

```
sed -e '/VK_EXT_surface_maintenance1/d' -e '/VK_KHR_get_surface_capabilities2/s/,$//' -i   /etc/vulkan/implicit_layer.d/VkLayer_window_system_integration.json 
```

- **Error 2**： 

```
Segmentation fault 
```

- The system's built-in Vulkan driver needs to be removed:

```
rm -r /usr/share/vulkan
```



### 3. Network Issues

#### 3.1 Solution for Dual Network Cards Displayed in Settings > Network

- Modify the configuration as follows:

```
sudo sed -i 's/NAME=\"$env{ID_NET_NAME}\"/NAME=\"$env{ID_NET_SLOT}\"/' /usr/lib/udev/rules.d/80-net-setup-link.rules sudo sed -i "/ACTION!=\"add|change|move\",/aENV{INTERFACE}==\"*p2p*\", ENV{NM_UNMANAGED}=\"1\"" /usr/lib/udev/rules.d/85-nm-unmanaged.rules 
```

**Note: The above modifications may introduce a probability of the eth0 and eth1 interface names being swapped in the Settings.**

#### 3.2 Device Cannot Access the Internet After Connecting to a Wi-Fi Hotspot

- The routing configuration is not added by default in the image. Users need to add it manually:

```
iptables -t nat -A POSTROUTING -s 10.42.0.1/24 -o ethx -j MASQUERADE
```
