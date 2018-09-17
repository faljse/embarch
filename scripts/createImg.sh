#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Philip Huppert
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
# the Software, and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
# FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
# IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

PARTITION="root.img"

HOSTNAME="embarch"
PASSWORD="root"
USERNAME="embarch"

TIMEZONE="Europe/Vienna"
CONSOLE_KEYMAP="de-latin1"
CONSOLE_FONT="lat9w-16"

PACBASE="
sed
bash
coreutils
e2fsprogs
gawk
gettext
glibc
grep
gzip
vi
pacman
pacman-mirrorlist
openssh
linux-raspberrypi
raspberrypi-bootloader
raspberrypi-firmware
tar
shadow
which
util-linux
"

PACEXTRA="
bzip2
procps-ng
nano
iproute2
connman
usbutils
wpa_supplicant
"

PACSTRAP="$PACBASE $PACEXTRA"
# PACSTRAP="$PACBASE"


function announce {
	>&2 echo -n "$1"
}

function check_fail {
	if [[ $1 -ne 0 ]]; then
		>&2 echo "FAIL!"
		exit 1
	else
		>&2 echo "OK!"
	fi
}

function lbSetup {
announce "create root.img file... "
truncate -s 2000M $PARTITION
check_fail $?

# announce "create loopback device "
# losetup /dev/loop0 card.img
# check_fail $?
}

function prepareDisk {
announce "Checking internet connectivity... "
wget -q --tries=10 --timeout=20 --spider http://google.de
check_fail $?


announce "Formatting root partition with ext4... "
mkfs.ext4 -F "$PARTITION"
check_fail $?
}

function mountParts {
announce "Mounting partition... "
mkdir -p "/mnt/root"
mount "$PARTITION" /mnt/root
check_fail $?
}

function installBase {
announce "Installing base system... "
pacstrap -c /mnt/root $PACSTRAP
check_fail $?
}


function configure {

announce "Setting root password... "
echo "root:$PASSWORD" | arch-chroot /mnt/root chpasswd 
check_fail $?

announce "Setting hostname... "
echo "$HOSTNAME" > /mnt/root/etc/hostname
check_fail $?


announce "Configuring root's bash... "
cp /mnt/root/etc/skel/.bash* /mnt/root
check_fail $?

announce "Configuring root's bashrc... "
cat <<EOF > /mnt/root/root/.bashrc
#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ \$- != *i* ]] && return

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=10000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

alias ls='ls --color=auto'
alias ll='ls -halF'
alias l='ls -hlF'

alias rm='rm -i'
alias mv='mv -i'
alias cp='cp -i'

alias cd..='cd ..'
alias j='jobs'

PS1='[\u@\h \W]\\$ '

EOF
check_fail $?


announce "Setting timezone... "
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/root/etc/localtime
check_fail $?

announce "Enabling locales... "
sed -i 's/^#en_US\.UTF/en_US\.UTF/' /mnt/root/etc/locale.gen && sed -i 's/^#de_DE\.UTF/de_DE\.UTF/' /mnt/root/etc/locale.gen
check_fail $?

announce "Configuring locales... "
cat <<EOF > /mnt/root/etc/locale.conf
LANG="en_US.UTF-8"
LC_CTYPE="de_DE.UTF-8"
LC_NUMERIC="de_DE.UTF-8"
LC_TIME="de_DE.UTF-8"
LC_COLLATE="de_DE.UTF-8"
LC_MONETARY="de_DE.UTF-8"
LC_MESSAGES="en_US.UTF-8"
LC_PAPER="de_DE.UTF-8"
LC_NAME="de_DE.UTF-8"
LC_ADDRESS="de_DE.UTF-8"
LC_TELEPHONE="de_DE.UTF-8"
LC_MEASUREMENT="de_DE.UTF-8"
LC_IDENTIFICATION="de_DE.UTF-8"
EOF
check_fail $?

announce "Configuring vconsole... "
echo -en "KEYMAP=$CONSOLE_KEYMAP\nFONT=$CONSOLE_FONT\n" > /mnt/root/etc/vconsole.conf
check_fail $?

announce "Generating locales... "
arch-chroot /mnt/root locale-gen
check_fail $?


announce "create user... "
arch-chroot /mnt/root useradd -m -U -G wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:pass" | arch-chroot /mnt/root chpasswd 
# check_fail $?


announce "Configuring interface names... "
ln -sf /dev/null /mnt/root/etc/udev/rules.d/80-net-setup-link.rules
check_fail $?

announce "Enabling DNS... "
arch-chroot /mnt/root systemctl enable systemd-resolved
check_fail $?

announce "Configuring NTP... "
sed -i 's/^#NTP=$/NTP=0.de.pool.ntp.org 1.de.pool.ntp.org 2.de.pool.ntp.org 3.de.pool.ntp.org/' /mnt/root/etc/systemd/timesyncd.conf
check_fail $?

announce "Generating first-boot script... "
cat <<EOF > /mnt/root/firstboot.sh
#!/bin/bash
timedatectl set-ntp true
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
systemctl disable firstboot.service
rm -f /etc/systemd/system/firstboot.service
rm -f /firstboot.sh
EOF
check_fail $?

announce "Generating first-boot service... "
cat <<EOF > /mnt/root/etc/systemd/system/firstboot.service
[Unit]
Description=Configuration script for first boot of system
After=basic.target

[Service]
Type=oneshot
User=root
ExecStart=/bin/bash /firstboot.sh

[Install]
WantedBy=basic.target
EOF
check_fail $?

announce "Generating fstab.."
cat <<EOF > /mnt/root/etc/fstab
/dev/loop0  	/	ext4    loop,ro        0       1
tmpfs           /tmp            tmpfs   nodev,nosuid,size=50M   0       0
tmpfs           /var/tmp        tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /var/log        tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /var/cache      tmpfs   nodev,nosuid,size=10M   0       0
tmpfs           /run            tmpfs   nodev,nosuid,size=20M   0       0
tmpfs           /home/embarch     tmpfs   nodev,nosuid,size=50M,uid=embarch,gid=embarch       0       0
EOF
check_fail $?



announce "generate ssh host keys "
arch-chroot /mnt/root ssh-keygen -A
check_fail $?


announce "copy config files... "
cp config.txt /mnt/root/boot/
cp cmdline.txt /mnt/root/boot/
cp initcpio/mkinitcpio.conf /mnt/root/etc/
cp initcpio/hooks/looproot /mnt/root/etc/initcpio/hooks/
cp initcpio/install/looproot /mnt/root/etc/initcpio/install/
arch-chroot /mnt/root mkinitcpio -p linux-raspberrypi

cp connman.conf /mnt/root/etc/dbus-1/system.d/
cp 10-rules.rules /mnt/root/etc/polkit-1/rules.d/
cp services/* /mnt/root/etc/systemd/system/
echo "connman"
arch-chroot /mnt/root systemctl enable connman
echo "sshd"
arch-chroot /mnt/root systemctl enable sshd

echo "disable rfkill"
arch-chroot /mnt/root systemctl disable systemd-rfkill

# echo "firstboot"
# arch-chroot /mnt/root systemctl enable firstboot.service
check_fail $?

echo "copy sdcard files"
mkdir ../sdcard
cp -r /mnt/root/boot/* ../sdcard

echo "systemd config"
echo "RuntimeWatchdogSec=15" >> /mnt/root/etc/systemd/system.conf
echo "ShutdownWatchdogSec=15" >> /mnt/root/etc/systemd/system.conf
echo "Storage=volatile" >> /mnt/root/etc/systemd/journald.conf

}

lbSetup
prepareDisk
mountParts
installBase
configure
umount /mnt/root
7z -mmt4 -mx3 a ../sdcard/root.img.7z root.img
