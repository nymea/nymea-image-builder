#!/bin/bash

#------------------------------------------------------------------------------------------
trapCallback() {
    errorCode="$?"

    if [ "${errorCode}" != "0" ]; then
        printRed "Error occured: exit status ${errorCode}"
        printRed "Clean up and umount possible mounted paths"
        umountAll
    fi

    exit ${errorCode}
}

#------------------------------------------------------------------------------------------
umountAll() {
    printGreen "Umount all mount points"

    for IMAGEMOUNT in ${MOUNT_DIR}/boot ${MOUNT_DIR}; do
        if mount | grep "$IMAGEMOUNT" > /dev/null; then
            printGreen "--> Umount image partition ${IMAGEMOUNT}"
            umount -l "${IMAGEMOUNT}"
        else
            printOrange "--> ${IMAGEMOUNT} is not mounted"
        fi
    done


    for MOUNTPOINT in $BOOTSTRAP $BASE $NYMEA $ROOTFS; do
        for SYSTEMMOUNTPOINT in $MOUNTPOINT/proc $MOUNTPOINT/sys $MOUNTPOINT/dev/pts $MOUNTPOINT/dev; do
            if mount | grep "$SYSTEMMOUNTPOINT" > /dev/null; then
                printGreen "--> Umount system from ${SYSTEMMOUNTPOINT}"
                umount -l "${SYSTEMMOUNTPOINT}"
            else
                printOrange "--> ${SYSTEMMOUNTPOINT} is not mounted"
            fi
        done
    done
}

#------------------------------------------------------------------------------------------
initEnv() {
    SCRIPT_DIR="$(pwd)"
    BUILD_DIR="${SCRIPT_DIR}/build"
    IMAGE_DIR="${BUILD_DIR}/${NAME}"
    MOUNT_DIR="${IMAGE_DIR}/mount"
    NYMEA="${IMAGE_DIR}/nymea"
    ROOTFS="${IMAGE_DIR}/rootfs"

    # Base dirs shared across builds
    BOOTSTRAP=${BUILD_DIR}/bootstrap/${TITLE}-${RELEASE}
    BOOTSTRAP_FLAG=${BUILD_DIR}/bootstrap/.${TITLE}-${RELEASE}
    BASE=${BUILD_DIR}/base/${TITLE}-${RELEASE}
    BASE_FLAG=${BUILD_DIR}/base/.${TITLE}-${RELEASE}
    NYMEA=${BUILD_DIR}/nymea/${TITLE}-${RELEASE}
    NYMEA_FLAG=${BUILD_DIR}/nymea/.${TITLE}-${RELEASE}

    NYMEA_REPOSITORY_SECTIONS="main"

    # Build env
    STARTTIME=$(date +%s)
    ARCH=$(uname -m)

    # Trap for unmounting on failure
    trap trapCallback EXIT SIGINT

    # Output file names
    FSTYPE="ext4"
    IMAGE_NAME="$(date +%Y-%m-%d)-${NAME}-${TITLE}-${RELEASE}-${VERSION}-armhf-raspberry-pi-3"
    TARBALL="${IMAGE_NAME}-rootfs.tar.bz2"
    IMAGE="${IMAGE_NAME}.img"

    # Bash colors
    BASH_GREEN="\e[1;32m"
    BASH_ORANGE="\e[33m"
    BASH_RED="\e[1;31m"
    BASH_NORMAL="\e[0m"

    # Create directories
    if [ ! -d $BUILD_DIR ]; then mkdir -pv $BUILD_DIR; fi
    if [ ! -d $IMAGE_DIR ]; then mkdir -pv $IMAGE_DIR; fi

    printGreen "Initialize environment"
    printGreen "--> Image build directory: ${IMAGE_DIR}"
    printGreen "--> Image bootstrap directory: ${BOOTSTRAP}"
    printGreen "--> Image base directory: ${BASE}"
    printGreen "--> Image nymea directory: ${NYMEA}"
    printGreen "--> Image rootfs directory: ${ROOTFS}"
    printGreen "--> Image mount directory: ${MOUNT_DIR}"
    printGreen "--> Image name: ${IMAGE_NAME}"

    umountAll
}

#------------------------------------------------------------------------------------------
cleanBuild() {
    printGreen "Clean build"
    umountAll
    rm -rf ${IMAGE_DIR}
    rm -rf ${NYMEA}
    rm -f ${NYMEA_FLAG}
}

#------------------------------------------------------------------------------------------
printGreen() {
    if ${COLORS}; then
        echo -e "${BASH_GREEN}[+] $1${BASH_NORMAL}"
    else
        echo -e "[+] $1"
    fi
}

#------------------------------------------------------------------------------------------
printOrange() {
    if ${COLORS}; then
        echo -e "${BASH_ORANGE}[-] $1${BASH_NORMAL}"
    else
        echo -e "[-] $1"
    fi
}

#------------------------------------------------------------------------------------------
printRed() {
    if ${COLORS}; then
        echo -e "${BASH_RED}[!] $1${BASH_NORMAL}"
    else
        echo -e "[!] $1"
    fi
}

#------------------------------------------------------------------------------------------
printTime() {
    # calculate process time
    endTime=$(date +%s)
    dt=$((endTime - STARTTIME))
    ds=$((dt % 60))
    dm=$(((dt / 60) % 60))
    dh=$((dt / 3600))

    echo -e "${BASH_GREEN}"
    echo -e "-------------------------------------------------------"
    printf '\tTotal time: %02d:%02d:%02d\n' ${dh} ${dm} ${ds}
    echo -e "-------------------------------------------------------"
    echo -e "${BASH_NORMAL}"
}

#------------------------------------------------------------------------------------------
checkRoot() {
    if [ ${UID} -ne 0 ]; then
        printRed "Please start the script as root."
        exit 1
    fi
}

#------------------------------------------------------------------------------------------
mountSystem() {
    printGreen "Mount system $R"
    # In case this is a re-run move the cofi preload out of the way
    if [ -e $R/etc/ld.so.preload ]; then
        mv -v $R/etc/ld.so.preload $R/etc/ld.so.preload.disable
    fi

    mount -t proc none $R/proc
    mount -t sysfs none $R/sys
    mount -o bind /dev $R/dev
    mount -o bind /dev/pts $R/dev/pts
}

#------------------------------------------------------------------------------------------
umountSystem() {
    printGreen "Umount system $R"
    umount -l $R/sys || true
    umount -l $R/proc || true
    umount -l $R/dev/pts || true
    umount -l $R/dev || true
}

#------------------------------------------------------------------------------------------
# $1 = source $2 = target
syncRootfs() {
    printGreen "Sync ${1} --> ${2}"
    if [ ! -d "${1}" ]; then mkdir -pv "${1}"; fi
    rsync -a --delete $1/ $2/
}

#------------------------------------------------------------------------------------------
addDebianSource() {
    printGreen "Add debian ${RELEASE} source lists to $R"
    cat <<EOM >$R/etc/apt/sources.list
deb http://http.debian.net/debian ${RELEASE} main contrib non-free
deb-src http://http.debian.net/debian ${RELEASE} main contrib non-free
deb http://security.debian.org/debian-security ${RELEASE}/updates main contrib non-free
EOM

    cat $R/etc/apt/sources.list
}

#------------------------------------------------------------------------------------------
generateLocale() {
    printGreen "Generate locale..."
    chroot $R apt-get -y install locales
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' $R/etc/locale.gen
    chroot $R locale-gen en_US.UTF-8
    echo -e "LC_ALL=en_US.UTF-8\nLANGUAGE=en_US.UTF-8" >> $R/etc/default/locale
}

#------------------------------------------------------------------------------------------
configureTimezone() {
    printGreen "Configure timezone ${TZDATA}..."
    echo ${TZDATA} > $R/etc/timezone
    chroot $R dpkg-reconfigure -f noninteractive tzdata
}

#------------------------------------------------------------------------------------------
createUser() {
    printGreen "Create ${USERNAME} user..."
    local DATE=$(date +%m%H%M%S)
    local PASSWD=$(mkpasswd -m sha-512 ${USERNAME} ${DATE})

    chroot $R adduser --gecos "nymea user" --add_extra_groups --disabled-password ${USERNAME}
    chroot $R usermod -a -G sudo -p ${PASSWD} ${USERNAME}
}

#------------------------------------------------------------------------------------------
createGroups() {
    printGreen "Create groups..."
    chroot $R groupadd -f --system gpio
    chroot $R groupadd -f --system i2c
    chroot $R groupadd -f --system input
    chroot $R groupadd -f --system spi
    chroot $R groupadd -f --system netdev
    chroot $R groupadd -f --system bluetooth
    chroot $R groupadd -f --system avahi

    # Create adduser hook
    cp -v ${SCRIPT_DIR}/files/adduser.local $R/usr/local/sbin/
    chmod +x $R/usr/local/sbin/adduser.local
}

#------------------------------------------------------------------------------------------
configureSsh() {
    printGreen "Configure ssh..."
    chroot $R apt-get -y install openssh-server sshguard
    cp -v ${SCRIPT_DIR}/files/sshdgenkeys.service $R/etc/systemd/system/
    mkdir -p $R/etc/systemd/system/ssh.service.wants

    chroot $R /bin/systemctl enable sshdgenkeys.service
    chroot $R /bin/systemctl enable ssh.service
    chroot $R /bin/systemctl enable sshguard.service
}

#------------------------------------------------------------------------------------------
configureNetwork() {
    printGreen "Set hostename ${HOSTNAME}..."

    # Set up hosts
    echo ${HOSTNAME} >$R/etc/hostname
    cat <<EOM >$R/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       ${HOSTNAME}
EOM

    # Set up interfaces
    printGreen "Configure network..."
    cat <<EOM >$R/etc/network/interfaces
# interfaces(5) file used by ifup(8) and ifdown(8)
# Include files from /etc/network/interfaces.d:
source-directory /etc/network/interfaces.d

# The loopback network interface
auto lo
iface lo inet loopback

# This will be handled by network-manager
#auto eth0
#iface eth0 inet dhcp
EOM

}

#------------------------------------------------------------------------------------------
configureBashrc() {
    printGreen "Add aliases to bashrc..."
    echo -e "\n# Custom alias for nice bash experience\n" >> $R/etc/bash.bashrc
    echo "alias ls='ls --color=auto'" >> $R/etc/bash.bashrc
    echo "alias ll='ls -lah'" >> $R/etc/bash.bashrc
}

#------------------------------------------------------------------------------------------
configureRaspberry() {

    printGreen "Configure welcome message..."
    # Welcome message
    cp -v ${SCRIPT_DIR}/lib/motd $R/etc/

    # Disable TLP
    if [ -f $R/etc/default/tlp ]; then
        sed -i s'/TLP_ENABLE=1/TLP_ENABLE=0/' $R/etc/default/tlp
    fi

    # Set up fstab
    printGreen "Set up fstab..."
    cat <<EOM >$R/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ${FSTYPE}   defaults,noatime  0       1
/dev/mmcblk0p1  /boot/          vfat    defaults          0       2
EOM

    # Set boot cmdline.txt
    printGreen "Configure cmdline.txt ..."
    echo "net.ifnames=0 biosdevname=0 fsck.repair=yes dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 rootfstype=${FSTYPE} elevator=deadline rootwait quiet splash init=/usr/lib/raspi-config/init_resize.sh" > $R/boot/cmdline.txt

    # Enable autoresize filesystem at first boot
    printGreen "Enable auto resize roofs on first boot ..."
    cp -v ${SCRIPT_DIR}/files/resize2fs_once $R/etc/init.d/resize2fs_once
    chmod +x $R/etc/init.d/resize2fs_once
    cp -v ${SCRIPT_DIR}/files/resize-fs.service $R/lib/systemd/system/resize-fs.service
    chroot $R /bin/systemctl enable resize-fs.service

    # Enable i2c
    echo "i2c-dev" >> $R/etc/modules
    echo "dtparam=i2c_arm=on" >> $R/boot/config.txt

    # TODO: configure gpu and other stuff

    # Save the clock
    chroot $R fake-hwclock save
}

#------------------------------------------------------------------------------------------
aptInstall() {
    packages="$@"
    printGreen "Install non interactive $packages"
    chroot $R /bin/bash -c -x "export DEBIAN_FRONTEND=noninteractive && apt-get -q -y --force-yes install ${packages}"
}

#------------------------------------------------------------------------------------------
aptUpgrade() {
    printGreen "Upgrade system $R ..."
    chroot $R apt-get update
    chroot $R apt-get -y -u dist-upgrade
}

#------------------------------------------------------------------------------------------
aptClean() {
    printGreen "Clean packages..."
    chroot $R apt-get -y autoremove
    chroot $R apt-get clean
}

#------------------------------------------------------------------------------------------
installDebianBase() {
    printGreen "Install debian default packages..."
    aptInstall f2fs-tools software-properties-common
    aptInstall adduser libc-bin apt apt-utils bzip2 console-setup debconf debconf-i18n eject gnupg ifupdown \
               initramfs-tools iproute2 iputils-ping isc-dhcp-client kbd kmod less nano locales lsb-release \
               makedev mawk net-tools netbase netcat-openbsd passwd procps python3 resolvconf rsyslog sudo \
               tzdata debian-keyring udev vim-tiny whiptail tcpdump telnet ufw cpio cron dnsutils \
               ed file ftp hdparm info iptables libpam-systemd logrotate lshw lsof \
               ltrace man-db mime-support parted pciutils psmisc rsync strace systemd-sysv time usbutils wget \
               apparmor apt-transport-https bash-completion command-not-found friendly-recovery iputils-tracepath \
               irqbalance manpages mlocate mtr-tiny ntfs-3g openssh-client uuid-runtime dirmngr

}

#------------------------------------------------------------------------------------------
installDebianRaspberryPi() {
    printGreen "Add Raspberry Pi debian repository..."
    cat <<EOM >$R/etc/apt/sources.list.d/raspberrypi.list
deb http://archive.raspberrypi.org/debian/ stretch main ui
#deb-src http://archive.raspberrypi.org/debian/ stretch main ui
EOM
    cat $R/etc/apt/sources.list.d/raspberrypi.list

    printGreen "Install Raspberry Pi repository key"
    chroot $R wget http://archive.raspberrypi.org/debian/raspberrypi.gpg.key
    chroot $R apt-key add raspberrypi.gpg.key
    rm -v $R/raspberrypi.gpg.key
    chroot $R apt-key list

    chroot $R apt update

    aptInstall libraspberrypi-bin libraspberrypi-dev libraspberrypi-doc libraspberrypi0 raspberrypi-bootloader rpi-update raspi-config \
               bluez-firmware pi-bluetooth raspi-copies-and-fills raspberrypi-sys-mods raspberrypi-net-mods \
               firmware-brcm80211 fake-hwclock fbset i2c-tools rng-tools raspi-gpio

}

#------------------------------------------------------------------------------------------
configureNymeaRepository() {
    printGreen "Add nymea repository..."

    # Add the nymea repository key
    chroot $R wget http://repository.nymea.io/repository-pubkey.gpg
    chroot $R apt-key add repository-pubkey.gpg
    rm -v $R/repository-pubkey.gpg;
    chroot $R apt-key list


    cat <<EOM >$R/etc/apt/sources.list.d/nymea.list
## nymea repository
deb http://repository.nymea.io ${RELEASE} ${NYMEA_REPOSITORY_SECTIONS}
deb-src http://repository.nymea.io ${RELEASE} ${NYMEA_REPOSITORY_SECTIONS}
EOM

    cat $R/etc/apt/sources.list.d/nymea.list
    chroot $R apt update
}

#------------------------------------------------------------------------------------------
cleanRootfs() {
    printGreen "Clean up rootfs $R ..."
    rm -f $R/etc/apt/*.save || true
    rm -f $R/etc/apt/sources.list.d/*.save || true
    rm -f $R/etc/resolvconf/resolv.conf.d/original
    rm -f $R/run/*/*pid || true
    rm -f $R/run/*pid || true
    rm -f $R/run/cups/cups.sock || true
    rm -f $R/run/uuidd/request || true
    rm -f $R/etc/*-
    rm -rf $R/tmp/*
    rm -f $R/var/crash/*
    rm -f $R/var/lib/urandom/random-seed

    # Build cruft
    rm -f $R/var/cache/debconf/*-old || true
    rm -f $R/var/lib/dpkg/*-old || true
    rm -f $R/var/cache/bootstrap.log || true
    truncate -s 0 $R/var/log/lastlog || true
    truncate -s 0 $R/var/log/faillog || true

    # SSH host keys
    rm -f $R/etc/ssh/ssh_host_*key
    rm -f $R/etc/ssh/ssh_host_*.pub

    # Clean up old Raspberry Pi firmware and modules
    rm -f $R/boot/.firmware_revision || true
    rm -rf $R/boot.bak || true
    rm -rf $R/lib/modules.bak || true

    # Potentially sensitive.
    rm -f $R/root/.bash_history
    rm -f $R/root/.ssh/known_hosts

    # Remove bogus home directory
    #rm -rf $R/home/${SUDO_USER} || true

    # Machine-specific, so remove in case this system is going to be
    # cloned.  These will be regenerated on the first boot.
    rm -f $R/etc/udev/rules.d/70-persistent-cd.rules
    rm -f $R/etc/udev/rules.d/70-persistent-net.rules
    rm -f $R/etc/NetworkManager/system-connections/*
    [ -L $R/var/lib/dbus/machine-id ] || rm -f $R/var/lib/dbus/machine-id
    echo '' > $R/etc/machine-id

    # Enable cofi
    if [ -e $R/etc/ld.so.preload.disabled ]; then
        mv -v $R/etc/ld.so.preload.disabled $R/etc/ld.so.preload
    fi

    rm -rf $R/tmp/.bootstrap || true
    rm -rf $R/tmp/.minimal || true
    rm -rf $R/tmp/.standard || true
}


#------------------------------------------------------------------------------------------
createImage() {

    cleanRootfs

    printGreen "Create image..."

    # Build the image file
    local FS="${FSTYPE}"
    local SIZE_IMG="${SIZE}"
    local SIZE_BOOT="64MiB"

    IMAGE_OUTPUT="${IMAGE_DIR}/${IMAGE}"

    # Create an empty file.
    dd if=/dev/zero of="${IMAGE_OUTPUT}" bs=1MB count=1
    dd if=/dev/zero of="${IMAGE_OUTPUT}" bs=1MB count=0 seek=$(( ${SIZE_IMG} * 1000 ))

    # Initialising boot patition: msdos
    parted -s ${IMAGE_OUTPUT} mktable msdos
    printGreen "Creating /boot partition"
    parted -a optimal -s ${IMAGE_OUTPUT} mkpart primary fat32 1 "${SIZE_BOOT}"
    printGreen "Creating /root partition"
    parted -a optimal -s ${IMAGE_OUTPUT} mkpart primary ext4 "${SIZE_BOOT}" 100%

    PARTED_OUT=$(parted -s ${IMAGE_OUTPUT} unit b print)
    BOOT_OFFSET=$(echo "${PARTED_OUT}" | grep -e '^ 1'| xargs echo -n \
    | cut -d" " -f 2 | tr -d B)
    BOOT_LENGTH=$(echo "${PARTED_OUT}" | grep -e '^ 1'| xargs echo -n \
    | cut -d" " -f 4 | tr -d B)

    ROOT_OFFSET=$(echo "${PARTED_OUT}" | grep -e '^ 2'| xargs echo -n \
    | cut -d" " -f 2 | tr -d B)
    ROOT_LENGTH=$(echo "${PARTED_OUT}" | grep -e '^ 2'| xargs echo -n \
    | cut -d" " -f 4 | tr -d B)

    BOOT_LOOP=$(losetup --show -f -o ${BOOT_OFFSET} --sizelimit ${BOOT_LENGTH} ${IMAGE_OUTPUT})
    ROOT_LOOP=$(losetup --show -f -o ${ROOT_OFFSET} --sizelimit ${ROOT_LENGTH} ${IMAGE_OUTPUT})
    printGreen "/boot: offset ${BOOT_OFFSET}, length ${BOOT_LENGTH}"
    printGreen "/:     offset ${ROOT_OFFSET}, length ${ROOT_LENGTH}"

    mkfs.vfat -n PI_BOOT -S 512 -s 16 -v "${BOOT_LOOP}"
    mkfs.ext4 -L PI_ROOT -m 0 -O ^huge_file "${ROOT_LOOP}"

    printGreen "Mount image into ${MOUNT_DIR}"
    if [ ! -d ${MOUNT_DIR} ]; then mkdir -pv ${MOUNT_DIR}; fi
    mount -v "${ROOT_LOOP}" "${MOUNT_DIR}" -t "${FS}"

    printGreen "Mount boot partition into ${MOUNT_DIR}/boot"
    if [ ! -d ${MOUNT_DIR}/boot ]; then mkdir -pv ${MOUNT_DIR}/boot; fi
    mount -v "${BOOT_LOOP}" "${MOUNT_DIR}/boot" -t vfat

    printGreen "Copy final rootfs into mounted image"
    rsync -aHAXx "$R/" "${MOUNT_DIR}/"
    sync
    printGreen "Umount final image"
    umount -l "${MOUNT_DIR}/boot"
    umount -l "${MOUNT_DIR}"
    losetup -d "${ROOT_LOOP}"
    losetup -d "${BOOT_LOOP}"

    printGreen "Compress ${IMAGE_NAME}.zip ..."
    cd ${IMAGE_DIR}
    zip ${IMAGE_NAME}.zip ${IMAGE}

    printGreen "Compress ${IMAGE}.xz ..."
    xz -z ${IMAGE}

    printGreen "Done."
    ls -lh ${IMAGE}*

    printGreen "Move final image files"
    mv -v ${IMAGE}.xz ${SCRIPT_DIR}
    mv -v ${IMAGE_NAME}.zip ${SCRIPT_DIR}
}

#------------------------------------------------------------------------------------------
bootstrapDebian() {
    printGreen "Bootstrap debian stretch"
    if [ -f $BOOTSTRAP_FLAG ]; then
        printGreen "Bootstrap already done. Using rootfs ${BOOTSTRAP}"
        return 0
    fi

    if [ ! -d ${BOOTSTRAP} ]; then mkdir -pv ${BOOTSTRAP}; fi

    if [ "${ARCH}" == "armv7l" ]; then
        debootstrap --verbose $RELEASE $BOOTSTRAP http://http.debian.net/debian
    else
        qemu-debootstrap --verbose --arch=armhf $RELEASE $BOOTSTRAP http://http.debian.net/debian
    fi
    touch $BOOTSTRAP_FLAG
    printGreen "Bootstrap debian stretch finished successfully."
}

#------------------------------------------------------------------------------------------
buildBaseSystemDebian() {

    bootstrapDebian

    printGreen "Build debian ${RELEASE} base system ${BASE}"
    R=${BASE}
    if [ ! -d ${R} ]; then mkdir -pv ${R}; fi

    if [ -f ${BASE_FLAG} ]; then
        printGreen "Debian ${RELEASE} base system already created. Skipping..."
        return 0
    else
        printGreen "Build debian stretch base system."
        syncRootfs ${BOOTSTRAP} ${R}
        mountSystem
        addDebianSource
        aptUpgrade
        generateLocale
        installDebianBase
        aptClean
        umountSystem
        touch ${BASE_FLAG}
        printGreen "Debian stretch base system built successfully."
    fi

    printGreen "Base system initialized successfully in ${R}"
}

#------------------------------------------------------------------------------------------
buildNymeaSystemDebian() {

    buildBaseSystemDebian

    printGreen "Build nymea debian ${RELEASE} system ${NYMEA}"
    R=${NYMEA}
    if [ ! -d ${R} ]; then mkdir -pv ${R}; fi

    if [ -f ${NYMEA_FLAG} ]; then
        printGreen "Debian ${RELEASE} nymea system already created. Update the nymea system..."
        mountSystem
        aptUpgrade
        aptClean
        umountSystem
    else
        printGreen "Build nymea debian stretch system."
        syncRootfs ${BASE} ${R}
        mountSystem

        # Configure base system to nymea

        configureTimezone
        createGroups
        createUser
        configureSsh
        configureNetwork
        configureBashrc

        installDebianRaspberryPi
        configureRaspberry

        aptUpgrade
        aptClean

        umountSystem
        touch ${NYMEA_FLAG}
        printGreen "Debian stretch nymea system built successfully."
    fi

    R=${ROOTFS}
    syncRootfs ${NYMEA} ${R}
    printGreen "Nymea system created successfully in ${R}"
}
