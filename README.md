# embarch
Embedded arch img creation tool

# What
Runs arch on a raspberry pi from a fat formatted thumb drive containing root.img

# Why
root.img can be replaced without special tools (dd, win32diskimager etc.) and permissions, making the update process accessible to most users.

# How
Needs to be run on an arch/arm host ([e.g. €0.006/hr scaleway](https://www.scaleway.com/virtual-cloud-servers/#anchor_arm))
```
cd scripts
./createImg
```
copy contents of ../sdcard onto thumb drive.
Make sure rpi is configured for usb boot ([bootcode.bin](https://github.com/raspberrypi/firmware/tree/master/boot))


# Customize
Todo
