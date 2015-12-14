# guh-image-builder
-----------------------------------------------------

This script builds an Ubuntu 15.04 Vivid image for Raspberry Pi 2 with a preinstalled guh setup. 

Install needed packages:
  
    $ sudo apt-get update
    $ sudo apt-get upgrade

    $ sudp apt-get install bmap-tools debootstrap qemu-utils

Build the image:

    $ sudo ./build-rpi2-ubuntu-image.sh

Flash the image to the micro SD card (minimum size 2GB):

> **Note:** Please replace `sdX` with the device of your SD card. You can use `lsblk` to check which device is your SD card. 


    $ sudo bmaptool copy --bmap ubuntu-image.bmap ubuntu-image.img /dev/sdX


Login:

    $ ssh guh@guh.local    # password guh

# Reference
-----------------------------------------------------

The script is based on the image build script from Ryan Finnie and can be found here:

https://wiki.ubuntu.com/ARM/RaspberryPi


# License
----------------------------------------------------

This is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
as published by the Free Software Foundation, version 2 of the License.
