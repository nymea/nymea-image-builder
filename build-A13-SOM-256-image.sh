#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#                                                                         #
#  Copyright (C) 2015-2017 Simon Stuerz <simon.stuerz@guh.io>             #
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


########################################################
# Configs
RELEASE="xenial"
VERSION="16.04"
HOSTNAME="guh"
USERNAME="guh"
TZDATA="Europe/Vienna"

# Directories
CURRENTDIR=$(pwd)
BASEDIR=${CURRENTDIR}/image-A13-SOM-256-build
MOUNTDIR="${BASEDIR}/mount"
BASEROOTFS=${BASEDIR}/base-rootfs
ROOTFS=${BASEDIR}/rootfs

# Build information
ARCH=$(uname -m)
CORES=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu)

# Image output
TARBALL="$(date +%Y-%m-%d)-guh-ubuntu-${VERSION}-armhf-rootfs.tar.bz2"
IMAGE_NAME="$(date +%Y-%m-%d)-guh-ubuntu-${VERSION}-armhf-A13-SOM-256"
IMAGE="${IMAGE_NAME}.img"

# Either 4, 8 or 16
FS_SIZE=4

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

#######################################################
init() {
    printGreen "Init..."
    if [ ! -d ${BASEDIR} ]; then
        printGreen "Creating base dir ${BASEDIR}"
        mkdir -p ${BASEDIR}
    fi

    #printGreen "Install packages"
    #sudo apt-get update
    #sudo apt-get install gcc-arm-linux-gnueabihf libncurses5-dev u-boot-tools build-essential git binfmt-support debootstrap \
    #f2fs-tools qemu-user-static rsync ubuntu-keyring wget whois device-tree-compiler
}


getToolChain() {
    printGreen "Get toolchain"
    cd ${BASEDIR}
    if [ ! -f gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz ]; then
        wget -c http://releases.linaro.org/components/toolchain/binaries/4.9-2016.02/arm-linux-gnueabihf/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz
    fi

    printGreen "Extract toolchain"
    if [ ! -d gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf ]; then
        tar xf gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf.tar.xz
    fi
    CC=${BASEDIR}/gcc-linaro-4.9-2016.02-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-
    ${CC}gcc --version
}

buildBootLoader() {
    printGreen "Get u-boot..."
    cd ${BASEDIR}
    if [ ! -d "u-boot-sunxi" ]; then
        #git clone git://git.denx.de/u-boot.git
        git clone -b sunxi https://github.com/GuhJenkins/u-boot-sunxi.git
    fi

    cd u-boot-sunxi

    # list available configurations
    grep sunxi boards.cfg | awk '{print $7}'

    printGreen "Configure u-boot..."
    make ARCH=arm CROSS_COMPILE=${CC} distclean
    make ARCH=arm CROSS_COMPILE=${CC} A13-OLinuXino-Micro_config

    printGreen "Build u-boot..."
    make -j${CORES} ARCH=arm CROSS_COMPILE=${CC}
}

buildKernel() {
    printGreen "Get kernel src..."
    cd ${BASEDIR}
    if [ ! -d "linux-sunxi" ]; then
        git clone https://github.com/GuhJenkins/linux-sunxi.git
    fi

    cd linux-sunxi

    printGreen "Configure kernel..."
    make ARCH=arm a13_micro_SOM_defconfig

    #make ARCH=arm menuconfig

    printGreen "Build kernel..."
    make -j${CORES} ARCH=arm CROSS_COMPILE=${CC} uImage

    printGreen "Build and install modules..."
    make -j${CORES} ARCH=arm CROSS_COMPILE=${CC} INSTALL_MOD_PATH=out modules
    make -j${CORES} ARCH=arm CROSS_COMPILE=${CC} INSTALL_MOD_PATH=out modules_install
}

bootstrap() {
    printGreen "Bootstrap..."

    if [ ! -f "${R}/tmp/.bootstrap" ]; then
        if [ "${ARCH}" == "armv7l" ]; then
            debootstrap --verbose $RELEASE $R http://ports.ubuntu.com/
        else
            qemu-debootstrap --verbose --arch=armhf $RELEASE $R http://ports.ubuntu.com/
        fi
        touch "$R/tmp/.bootstrap"
    else
        printGreen "Skipping bootstrap: using existing one in ${R}"
    fi
}

function install_ubuntu() {
    printGreen "Install ubuntu..."
    chroot $R apt-get -y install f2fs-tools software-properties-common
    if [ ! -f "${R}/tmp/.ubuntu" ]; then
        chroot $R apt-get -y install ubuntu-standard
        touch "${R}/tmp/.ubuntu"
    fi
}

function mountSystem() {
    printGreen "Mount system..."
    # In case this is a re-run move the cofi preload out of the way
    if [ -e $R/etc/ld.so.preload ]; then
        mv -v $R/etc/ld.so.preload $R/etc/ld.so.preload.disable
    fi

    mount -t proc none $R/proc
    mount -t sysfs none $R/sys
    mount -o bind /dev $R/dev
    mount -o bind /dev/pts $R/dev/pts
    echo "nameserver 8.8.8.8" > $R/etc/resolv.conf
}

function umountSystem() {
    printGreen "Umount system..."
    umount -l $R/sys
    umount -l $R/proc
    umount -l $R/dev/pts
    umount -l $R/dev
    echo "" > $R/etc/resolv.conf
}

function aptSources() {
    printGreen "Add source lists..."
    cat <<EOM >$R/etc/apt/sources.list
deb http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE} main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-updates main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-security main restricted universe multiverse

deb http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
deb-src http://ports.ubuntu.com/ ${RELEASE}-backports main restricted universe multiverse
EOM
}

function aptUpgrade() {
    printGreen "Upgrade..."
    chroot $R apt-get update
    chroot $R apt-get -y -u dist-upgrade
}

function aptClean() {
    printGreen "Clean packages..."
    chroot $R apt-get -y autoremove
    chroot $R apt-get clean
}

function syncTo() {
    local TARGET="${1}"
    if [ ! -d "${TARGET}" ]; then
        mkdir -p "${TARGET}"
    fi
    printGreen "Sync to ${1}..."
    rsync -a --progress --delete ${R}/ ${TARGET}/
}

function generateLocale() {
    printGreen "Generate locale..."
    for LOCALE in $(chroot $R locale | cut -d'=' -f2 | grep -v : | sed 's/"//g' | uniq); do
        if [ -n "${LOCALE}" ]; then
            chroot $R locale-gen $LOCALE
        fi
    done
}

function configureTimezone() {
    printGreen "Setup timezone ${TZDATA}..."
    # Set time zone
    echo ${TZDATA} > $R/etc/timezone
    chroot $R dpkg-reconfigure -f noninteractive tzdata
}

# Create default user
function createUser() {
    printGreen "Create user ${USERNAME}:${USERNAME} ..."
    local DATE=$(date +%m%H%M%S)
    local PASSWD=$(mkpasswd -m sha-512 ${USERNAME} ${DATE})

    chroot $R adduser --gecos "guh user" --add_extra_groups --disabled-password ${USERNAME}
    chroot $R usermod -a -G sudo -p ${PASSWD} ${USERNAME}
}

function installSoftware() {

    printGreen "Add guh repository..."
    cat <<EOM >$R/etc/apt/sources.list.d/guh.list
## guh repo
deb http://repository.guh.io ${RELEASE} main
deb-src http://repository.guh.io ${RELEASE} main
EOM

    # Add the guh repository key
    chroot $R apt-key adv --keyserver keyserver.ubuntu.com --recv-key A1A19ED6

    printGreen "Update..."
    chroot $R apt-get update

    printGreen "Install extra packages..."
    chroot $R apt-get -y install htop nano avahi-utils

    printGreen "Install guh packages..."
    chroot $R apt-get -y install guh guh-cli guh-webinterface

    printGreen "Enable guhd autostart..."
    chroot $R systemctl enable guhd
}

function createImage() {
printGreen "Create image..."
    # Build the image file
    local GB=${2}

    if [ ${GB} -ne 4 ] && [ ${GB} -ne 8 ] && [ ${GB} -ne 16 ]; then
        printRed "ERROR! Unsupport card image size requested. Exitting."
        exit 1
    fi

    if [ ${GB} -eq 4 ]; then
        SEEK=3750
        SIZE=7546880
        SIZE_LIMIT=3685
    elif [ ${GB} -eq 8 ]; then
        SEEK=7680
        SIZE=15728639
        SIZE_LIMIT=7615
    elif [ ${GB} -eq 16 ]; then
        SEEK=15360
        SIZE=31457278
        SIZE_LIMIT=15230
    fi

    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=1
    dd if=/dev/zero of="${BASEDIR}/${IMAGE}" bs=1M count=0 seek=${SEEK}

    sfdisk -f "$BASEDIR/${IMAGE}" <<EOM
unit: sectors

1 : start=     2048, size=   131072, Id= c, bootable
2 : start=   133120, size=  ${SIZE}, Id=83
3 : start=        0, size=        0, Id= 0
4 : start=        0, size=        0, Id= 0
EOM

    BOOT_LOOP="$(losetup -o 1M --sizelimit 64M -f --show ${BASEDIR}/${IMAGE})"
    ROOT_LOOP="$(losetup -o 65M --sizelimit ${SIZE_LIMIT}M -f --show ${BASEDIR}/${IMAGE})"

    mkfs.vfat -n BOOT -S 512 -s 16 -v "${BOOT_LOOP}"
    mkfs.ext3 -L ROOTFS -m 0 "${ROOT_LOOP}"

    mount "${ROOT_LOOP}" "${MOUNTDIR}"
    mkdir -p "${MOUNTDIR}/boot"

    mkdir -p "${MOUNTDIR}/rootfs"
    mount "${BOOT_LOOP}" "${MOUNTDIR}/boot"

    rsync -a --progress "$R/" "${MOUNTDIR}/"

    umount -l "${MOUNTDIR}/boot"
    umount -l "${MOUNTDIR}/rootfs"

    losetup -d "${BOOT_LOOP}"
    losetup -d "${ROOT_LOOP}"
}


#######################################################################################################################

function buildKernelAndBootloader() {
    printGreen "=================================================================================="
    printGreen "Building u-boot and kernel"
    printGreen "=================================================================================="

    getToolChain
    buildBootLoader
    buildKernel
}

function buildBaseRootfs() {

    printGreen "=================================================================================="
    printGreen "Create basic ${RELEASE} rootfs"
    printGreen "=================================================================================="

    # Set R to base rootfs
    R=${BASEROOTFS}

    bootstrap
    mountSystem
    generateLocale
    configureTimezone
    aptSources
    aptUpgrade
    installUbuntu
    aptClean
    umountSystem
}

function buildRootfs() {
    # Create A13 SOM 256 rootfs
    printGreen "=================================================================================="
    printGreen "Create A13 SOM 256 ${RELEASE} rootfs"
    printGreen "=================================================================================="

    R=${BASEROOTFS}
    # Copy base rootfs to "rootfs"
    syncTo ${ROOTFS}
    # Continue working in final rootfs
    R=${ROOTFS}

    mountSystem
    createUser
    installSoftware
    aptClean
    umountSystem
}

function buildImage() {
    printGreen "=================================================================================="
    printGreen "Create image"
    printGreen "=================================================================================="

    

}


#######################################################################################################################
#######################################################################################################################

# Init dirs
init

# Build Kernel image, modules and u-boot bootloader
buildKernelAndBootloader

# Build the basic rootfs
buildBaseRootfs

# Build the final rootfs for the image
buildRootfs

