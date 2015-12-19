#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#                                                                         #
#  Copyright (C) 2015 Ryan Finnie <ryan@finnie.org>                       #
#  Copyright (C) 2015 Simon Stuerz <simon.stuerz@guh.guru>                #
#                                                                         #
#  This file is part of guh.                                              #
#                                                                         #
#  guh is free software: you can redistribute it and/or modify            #
#  it under the terms of the GNU General Public License as published by   #
#  the Free Software Foundation, version 2 of the License.                #
#                                                                         #
#  guh is distributed in the hope that it will be useful,                 #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of         #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the           #
#  GNU General Public License for more details.                           #
#                                                                         #
#  You should have received a copy of the GNU General Public License      #
#  along with guh. If not, see <http://www.gnu.org/licenses/>.            #
#                                                                         #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# The documantation of the original script can be found here: https://wiki.ubuntu.com/ARM/RaspberryPi
# The original script from Ryan Finnie can be found here: http://www.finnie.org/software/raspberrypi/rpi2-build-image.sh

set -e
#set -x

startTime=$(date +%s)

##########################################################
# Set the relase
RELEASE=vivid

# Image configs
HOSTNAME=guh
DEST_LANG="en_US.UTF-8"
TZDATA="Europe/Vienna"

#########################################################
# Directorys
BASEDIR=$(pwd)/image-build
BUILDDIR=${BASEDIR}/build
MOUNTDIR="$BUILDDIR/mount"

IMAGE_NAME=${BASEDIR}/$(date +%Y-%m-%d)-guh-ubuntu-rpi2-${RELEASE}

########################################################
# bash colors
BASH_GREEN="\e[1;32m"
BASH_RED="\e[1;31m"
BASH_NORMAL="\e[0m"

printGreen() {
    echo -e "${BASH_GREEN}$1${BASH_NORMAL}"
}

printRed() {
    echo -e "${BASH_RED}$1${BASH_NORMAL}"
}

#########################################################
# check root
if [ ${UID} -ne 0 ]; then
    printRed "Please start the script as root."
    exit 1
fi

#########################################################
# check build dir
if [ -d ${BUILDDIR} ]; then
    read -p "Build directory already exists. Do you want to delete is? [y/N] " response
    if [[ $response == "y" || $response == "Y" || $response == "yes" || $response == "Yes" ]]
    then
        printGreen "Delete ${BUILDDIR}"
        sudo rm -rf ${BUILDDIR}
    else
        exit 1
    fi
fi

# Set up environment
export TZ=UTC
R=${BUILDDIR}/chroot
mkdir -p $R

#########################################################
# Base debootstrap
printGreen "Start debootstrap ${R} ..."
apt-get -y install ubuntu-keyring
qemu-debootstrap --arch armhf $RELEASE $R http://ports.ubuntu.com/

# Mount required filesystems
printGreen "Mount filesystem ..."
mount -t proc none $R/proc
mount -t sysfs none $R/sys

printGreen "Create source list..."
cat <<EOM >$R/etc/apt/sources.list
deb http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse
deb http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse
deb http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
EOM

#########################################################
# Install the RPi PPA
printGreen "Install RPi2 PPAs..."
cat <<"EOM" >$R/etc/apt/preferences.d/rpi2-ppa
Package: *
Pin: release o=LP-PPA-fo0bar-rpi2
Pin-Priority: 990

Package: *
Pin: release o=LP-PPA-fo0bar-rpi2-staging
Pin-Priority: 990
EOM

#########################################################
printGreen "Update package list..."
chroot $R apt-get update
chroot $R apt-get -y -u dist-upgrade
chroot $R apt-get -y install software-properties-common ubuntu-keyring
chroot $R apt-add-repository -y ppa:fo0bar/rpi2

#########################################################
# Install guh repository
printGreen "Install guh repository..."
cat <<EOM >$R/etc/apt/sources.list.d/guh.list
## guh repo
deb http://repo.guh.guru ${RELEASE} main
deb-src http://repo.guh.guru ${RELEASE} main
EOM

# Add the guh repository key
chroot $R apt-key adv --keyserver keyserver.ubuntu.com --recv-key 6B9376B0

chroot $R apt-get update
chroot $R apt-get -y -u dist-upgrade

#########################################################
# Generate locales
printGreen "Generate locales..."
chroot $R apt-get -y -qq install locales language-pack-en
chroot $R locale-gen ${DEST_LANG}
chroot $R update-locale LANG=${DEST_LANG} LC_ALL=${DEST_LANG} LANGUAGE=${DEST_LANG} LC_MESSAGES=POSIX

printGreen "Setup timezone ${TZDATA}..."
# Set time zone
echo ${TZDATA} > $R/etc/timezone
chroot $R dpkg-reconfigure -f noninteractive tzdata

#########################################################
printGreen "Install standard packages..."
# Standard packages
chroot $R apt-get -y install ubuntu-standard initramfs-tools raspberrypi-bootloader-nokernel rpi2-ubuntu-errata openssh-server avahi-utils linux-firmware

# Extra packages
chroot $R apt-get -y install libraspberrypi-bin #libraspberrypi-dev

# Install guh packages
printGreen "Install guh packages..."
chroot $R apt-get -y install guh guh-cli guh-webinterface

#########################################################
# Kernel installation (Install flash-kernel last so it doesn't try (and fail) to detect the platform in the chroot.)
printGreen "Install kernel..."
chroot $R apt-get -y --no-install-recommends install linux-image-rpi2
chroot $R apt-get -y install flash-kernel

VMLINUZ="$(ls -1 $R/boot/vmlinuz-* | sort | tail -n 1)"
[ -z "$VMLINUZ" ] && exit 1
cp $VMLINUZ $R/boot/firmware/kernel7.img

INITRD="$(ls -1 $R/boot/initrd.img-* | sort | tail -n 1)"
[ -z "$INITRD" ] && exit 1
cp $INITRD $R/boot/firmware/initrd7.img

# Set up fstab
printGreen "Create fstab..."
cat <<EOM >$R/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
EOM

#########################################################
# Set up hosts
printGreen "Set hostename ${HOSTNAME}..."
echo ${HOSTNAME} >$R/etc/hostname
cat <<EOM >$R/etc/hosts
127.0.0.1       localhost
::1             localhost ${HOSTNAME} ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       ${HOSTNAME}
EOM

#########################################################
# Set up default user
printGreen "Create guh user..."
chroot $R adduser --gecos "guh user" --add_extra_groups --disabled-password guh
chroot $R usermod -a -G sudo,adm -p '$6$iTPEdlv4$HSmYhiw2FmvQfueq32X30NqsYKpGDoTAUV2mzmHEgP/1B7rV3vfsjZKnAWn6M2d.V2UsPuZ2nWHg1iqzIu/nF/' guh

# Clean cached downloads
printGreen "Clean up repository cache..."
chroot $R apt-get clean

printGreen "Enable guhd autostart..."
chroot $R systemctl enable guhd

#########################################################
# Set up interfaces
printGreen "Setup network configuration..."
cat <<EOM >$R/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp
EOM

#########################################################
# Set up firmware config
printGreen "Setup firmware config..."
cat <<EOM >$R/boot/firmware/config.txt
# For more options and information see
# http://www.raspberrypi.org/documentation/configuration/config-txt.md
# Some settings may impact device functionality. See link above for details

# uncomment if you get no picture on HDMI for a default "safe" mode
#hdmi_safe=1

# uncomment this if your display has a black border of unused pixels visible
# and your display can output without overscan
#disable_overscan=1

# uncomment the following to adjust overscan. Use positive numbers if console
# goes off screen, and negative if there is too much border
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# uncomment to force a console size. By default it will be display's size minus
# overscan.
#framebuffer_width=1280
#framebuffer_height=720

# uncomment if hdmi display is not detected and composite is being output
#hdmi_force_hotplug=1

# uncomment to force a specific HDMI mode (this will force VGA)
#hdmi_group=1
#hdmi_mode=1

# uncomment to force a HDMI mode rather than DVI. This can make audio work in
# DMT (computer monitor) modes
#hdmi_drive=2

# uncomment to increase signal to HDMI, if you have interference, blanking, or
# no display
#config_hdmi_boost=4

# uncomment for composite PAL
#sdtv_mode=2

#uncomment to overclock the arm. 700 MHz is the default.
#arm_freq=800
EOM

ln -sf firmware/config.txt $R/boot/config.txt
echo 'dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootwait' > $R/boot/firmware/cmdline.txt
ln -sf firmware/cmdline.txt $R/boot/cmdline.txt

#########################################################
# Load sound module on boot
printGreen "Load moduls..."
cat <<EOM >$R/lib/modules-load.d/rpi2.conf
snd_bcm2835
bcm2708_rng
EOM

# Blacklist platform modules not applicable to the RPi2
printGreen "Blacklist not applicable modules..."
cat <<EOM >$R/etc/modprobe.d/rpi2.conf
blacklist snd_soc_pcm512x_i2c
blacklist snd_soc_pcm512x
blacklist snd_soc_tas5713
blacklist snd_soc_wm8804
EOM

# Unmount mounted filesystems
printGreen "Umount proc and sys..."
umount -l $R/proc
umount -l $R/sys

#########################################################
# Clean up files
printGreen "Clean up files..."
rm -f $R/etc/apt/sources.list.save
rm -f $R/etc/resolvconf/resolv.conf.d/original
rm -rf $R/run
mkdir -p $R/run
rm -f $R/etc/*-
rm -f $R/root/.bash_history
rm -rf $R/tmp/*
rm -f $R/var/lib/urandom/random-seed
[ -L $R/var/lib/dbus/machine-id ] || rm -f $R/var/lib/dbus/machine-id
rm -f $R/etc/machine-id

#########################################################
# Build the image file
# Currently hardcoded to a 1.75GiB image
printGreen "Build image ${IMAGE_NAME}.img ..."
dd if=/dev/zero of="${IMAGE_NAME}.img" bs=1M count=1
dd if=/dev/zero of="${IMAGE_NAME}.img" bs=1M count=0 seek=1792
sfdisk -f "${IMAGE_NAME}.img" <<EOM
unit: sectors

1 : start=     2048, size=   131072, Id= c, bootable
2 : start=   133120, size=  3536896, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM

VFAT_LOOP="$(losetup -o 1M --sizelimit 64M -f --show ${IMAGE_NAME}.img)"
EXT4_LOOP="$(losetup -o 65M --sizelimit 1727M -f --show ${IMAGE_NAME}.img)"
mkfs.vfat "$VFAT_LOOP"
mkfs.ext4 "$EXT4_LOOP"
mkdir -p "$MOUNTDIR"
mount "$EXT4_LOOP" "$MOUNTDIR"
mkdir -p "$MOUNTDIR/boot/firmware"
mount "$VFAT_LOOP" "$MOUNTDIR/boot/firmware"
rsync -a "$R/" "$MOUNTDIR/"
umount "$MOUNTDIR/boot/firmware"
umount "$MOUNTDIR"
losetup -d "$EXT4_LOOP"
losetup -d "$VFAT_LOOP"
if which bmaptool; then
    bmaptool create -o "${IMAGE_NAME}.bmap" "${IMAGE_NAME}.img"
fi

#########################################################
ls -l
printGreen "Compress files ${IMAGE_NAME}.zip ..."
zip ${IMAGE_NAME} ${IMAGE_NAME}.bmap ${IMAGE_NAME}.img

#########################################################
# calculate process time
endTime=$(date +%s)
dt=$((endTime - startTime))
ds=$((dt % 60))
dm=$(((dt / 60) % 60))
dh=$((dt / 3600))

echo -e "${BASH_GREEN}"
echo -e "-------------------------------------------------------"
printf '\tTotal time: %02d:%02d:%02d\n' ${dh} ${dm} ${ds}
echo -e "-------------------------------------------------------"
echo -e "${BASH_NORMAL}"

