#!/bin/sh

# Mountpoints:
# /dev/sda1 /boot
# /dev/sda2 /
# /dev/sda3 /home
# /dev/sda4
# /dev/sda5 /var
# /dev/sda6 /var/log
# /dev/sda7 /var/log/audit
# /dev/sda8 /var/lib/docker

readonly DISK='/dev/sda'
readonly FS='ext4'
readonly HOME_PART=3
readonly VAR_PART=5
readonly LOG_PART=6
readonly AUDIT_PART=7
readonly DOCKER_PART=8
readonly HOME_PATH='/home'
readonly VAR_PATH='/var'
readonly LOG_PATH='/var/log'
readonly AUDIT_PATH='/var/log/audit'
readonly DOCKER_PATH='/var/lib/docker'


# Remount
mkdir -p "/mnt${HOME_PATH}"
mkdir -p "/mnt${VAR_PATH}"
mkdir -p "/mnt${LOG_PATH}"
mount "${DISK}${HOME_PART}" "/mnt${HOME_PATH}"
mount "${DISK}${VAR_PART}" "/mnt${VAR_PATH}"
mount "${DISK}${LOG_PART}" "/mnt${LOG_PATH}"
rsync -aqxP "${HOME_PATH}/" "/mnt${HOME_PATH}"
rsync -aqxP "${VAR_PATH}/" --exclude 'log' "/mnt${VAR_PATH}"
rsync -aqxP "${LOG_PATH}/" "/mnt${LOG_PATH}"

# Mount
mkdir -p /var/log/audit
mkdir -p /var/lib/docker
mount "${DISK}${AUDIT_PART}" "${AUDIT_PATH}"
mount "${DISK}${DOCKER_PART}" "${DOCKER_PATH}"

# Mount at boot
{
    echo "${DISK}${HOME_PART} ${HOME_PATH} ${FS} rw,nosuid,nodev 0 0"
    echo "${DISK}${VAR_PART} ${VAR_PATH} ${FS} defaults 0 0"
    echo "${DISK}${LOG_PART} ${LOG_PATH} ${FS} rw,nosuid,nodev,noexec 0 0"
    echo "${DISK}${AUDIT_PART} ${AUDIT_PATH} ${FS} rw,nosuid,nodev,noexec 0 0"
    echo "${DISK}${DOCKER_PART} ${DOCKER_PATH} ${FS} defaults 0 0"
} >> /etc/fstab

# reboot
# grub-mkpasswd-pbkdf2
# apt-get install git
# apt-get update && apt-get install net-tools
# git clone https://github.com/konstruktoid/hardening.git
# nano ubuntu.cfg
# bash ubuntu.sh
# reboot


