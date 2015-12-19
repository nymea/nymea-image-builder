# guh-image-builder
-----------------------------------------------------

This script builds an Ubuntu 15.04 Vivid image for Raspberry Pi 2 with a pre installed guh setup. 

### Install needed packages:
  
    $ sudo apt-get update
    $ sudo apt-get upgrade

    $ sudp apt-get install zip bmap-tools debootstrap qemu-utils


### Build the image:

    $ sudo ./build-rpi2-ubuntu-image.sh

-----------------------------------------------------

### Flash the image to the micro SD card (minimum size 2GB):

> **Note:** Please replace `sdX` with the device of your SD card. You can use `lsblk` to check which device is your SD card. 


    $ sudo bmaptool copy --bmap ubuntu-image.bmap ubuntu-image.img /dev/sdX

Once the process is finished you can insert the micro SD card into the Raspberry Pi 2, connect the ethernet cable and power it on.

-----------------------------------------------------

### Login 
You can try to connect to the Raspberry Pi 2 using the hostname of the device (`guh`):

    $ ssh guh@guh.local    # password: ubuntu


Depending on the network setup `avahi` sometimes does not work. In that case you can connect to the device using the ip address:

> **Note:** Please replace `192.168.0.X` with the ip of your Raspberry Pi 2.

    $ ssh guh@192.168.0.X    # password: ubuntu


-----------------------------------------------------

### guh-webinterface

Once the system is running on your Raspberry Pi 2 `guhd` should already running. You can connect to the guh-webinterface using following link:

> **Note:** If this link is not working, plase replace `guh.local` with the ip address of your Raspberry Pi 2.

    http://guh.local:3333
 
# Reference
-----------------------------------------------------

The script is based on the image build script from Ryan Finnie and can be found here:

https://wiki.ubuntu.com/ARM/RaspberryPi


# License
----------------------------------------------------

This is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License 
as published by the Free Software Foundation, version 2 of the License.
