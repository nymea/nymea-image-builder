# nymea-image-builder
-----------------------------------------------------

## Prebuilt images

Prebuilt images can be found here: https://downloads.nymea.io/images/

This script tools allow to build an Ubuntu 16.04 LTS Xenial Xerus image for different platforms containing a complete nymea setup. 

-----------------------------------------------------

## Building images

Assuming you are on an Ubuntu 16.04 (amd64).

### Install needed packages:
  
    $ sudo apt-get update
    $ sudo apt-get upgrade

    $ sudo apt-get install zip debootstrap qemu-utils xz-utils


### Build the image:

Here an example how to build an image (in this case Raspberry Pi 3):

    $ sudo ./build-rpi3-image.sh

Once finished you should find two compressed image files in the script directory (one for `zip`, one fox `xzcat`):

- `$(date +%Y-%m-%d)-guh-ubuntu-16.04.2-armhf-raspberry-pi-3.zip`
- `$(date +%Y-%m-%d)-guh-ubuntu-16.04.2-armhf-raspberry-pi-3.img.xz`


-----------------------------------------------------

### Flash the image to the micro SD card (minimum size 4GB):

#### Using xzcat

> **Note:** Please replace `sdX` with the device of your SD card. You can use `lsblk` to check which device is your SD card. 

    $ xzcat image-file.img.xz | sudo dd bs=4M of=/dev/sdX


#### Using zip file

> **Note:** Please replace `sdX` with the device of your SD card. You can use `lsblk` to check which device is your SD card. 

    $ unzip image-file.zip
    $ sudo dd if=image-file.img of=/dev/sdX bs=4M


Once the process is finished you can insert the micro SD card into your device, connect the ethernet cable and power it on.

-----------------------------------------------------

### Login 

The system will boot, create ssh keys, resize the file system and reboot again. Once that process is finished, you can try to connect 
to the your device using the hostname of the device (`nymea`):

    $ ssh nymea@nymea.local    # password: nymea


Depending on the network setup `avahi` sometimes does not work. In that case you can connect to the device using the ip address:

> **Note:** Please replace `192.168.0.X` with the ip of your Raspberry Pi 3.

    $ ssh nymea@192.168.0.X    # password: nymea

 
# Reference
-----------------------------------------------------

The script is based on the image build script from Ryan Finnie and can be found here:

https://wiki.ubuntu.com/ARM/RaspberryPi

And the Ubuntu Pi Flavour Maker team:

https://code.launchpad.net/ubuntu-pi-flavour-maker

# License
----------------------------------------------------

This is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
as published by the Free Software Foundation, version 2 of the License.

