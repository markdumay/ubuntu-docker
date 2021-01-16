#!/bin/sh

#======================================================================================================================
# Title         : createPartitions.sh
# Description   : Partition the Virtual Disk of a VM with Ubuntu 20.04 LTS
# Author        : Mark Dumay
# Date          : January 16th, 2021
# Version       : 0.5.0
# Usage         : createPartitions.sh <disk_name> <disk_size>
# Repository    : https://github.com/markdumay/ubuntu-docker.git
# License       : MIT - https://github.com/markdumay/ubuntu-docker/blob/master/LICENSE
# Credits       : Inspired by Hardening repository from Thomas Sjögren (https://github.com/konstruktoid/hardening/)
# Comments      : Portions copyrighted by Thomas Sjögren (konstruktoid), with Apache License 2.0
#======================================================================================================================


#======================================================================================================================
# This script creates the partitions of a virtual disk drive that is part of a virtual machine (VM) running Ubuntu. It 
# has been tested with Ubuntu 20.04 LTS (Focal Fossa). It is called inline by a Vagrantfile to partition the virtual 
# disk during boot of the VM. The script tests if a compatible drive is found. By default, `/dev/sdc` is used with an
# expected size of 5GiB, but these can changed by command-line arguments. The script aborts if no compatible drive is
# found. The virtual drive is reformatted, so any existing data is lost. The script creates four partitions, that act
# as mount point for the following directories:
# PARTITION SIZE        MOUNT POINT
# --------- ----        -----------
# /dev/sdc1   500MiB    /home
# /dev/sdc2 1.000MiB    /var
# /dev/sdc3   500MiB    /var/log
# /dev/sdc4 3.000MiB    /var/lib/docker
# 
# The script supports to optional arguments:
# $1 - disk name, defaults to 'sdc'
# $2 - disk size in GiB, defaults to '5G'
# 
# This script is based on an example developed by Thomas Sjögren (konstruktoid), whom also authored an Ansible playbook
# for the hardening of several Linux distributions, including Ubuntu 20.04 LTS. He is also the editor of the Docker 
# Bench for Security.
#======================================================================================================================

readonly HOME_PATH='/home'
readonly VAR_PATH='/var'
readonly LOG_PATH='/var/log'
readonly DOCKER_PATH='/var/lib/docker'

disk_name="${1:-'sdc'}"
disk_size="${2:-'5G'}"

if lsblk | grep "^${disk_name}.*${disk_size}"; then
    echo "Creating partitions and mount points for drive '${disk_name}' of size '${disk_size}'"

    # create four primary partitions, allocating remaining disk space to Docker 
    sgdisk -n 1:0:+500MiB  -t 1:8300 -c 1:home   /dev/sdc
    sgdisk -n 2:0:+1000MiB -t 2:8300 -c 2:var    /dev/sdc
    sgdisk -n 3:0:+500MiB  -t 3:8300 -c 3:log    /dev/sdc
    sgdisk -n 4:0:0        -t 4:8300 -c 4:docker /dev/sdc

    # format the four partitions
    mkfs.xfs /dev/sdc1
    mkfs.xfs /dev/sdc2
    mkfs.xfs /dev/sdc3
    mkfs.xfs /dev/sdc4

    # create temporary mount points
    mkdir -p "/media/home"
    mount -t xfs /dev/sdc1 "/media/home"
    mkdir -p "/media/var"
    mount -t xfs /dev/sdc2 "/media/var"
    mkdir -p "/media/log"
    mount -t xfs /dev/sdc3 "/media/log"

    # copy current data to new partitions
    rsync -aXS "${HOME_PATH}/." "/media/home/."
    rsync -aXS "${VAR_PATH}/." --exclude 'log' "/media/var/."
    rsync -aXS "${LOG_PATH}/." "/media/log/."

    # remove obsolete directories
    rm -rf "${HOME_PATH}"
    rm -rf "${VAR_PATH}"

    # remove temporary mount points
    umount /dev/sdc1
    umount /dev/sdc2
    umount /dev/sdc3

    # create final mount points
    mkdir -p "${HOME_PATH}"
    mount -t xfs /dev/sdc1 "${HOME_PATH}"
    mkdir -p "${VAR_PATH}"
    mount -t xfs /dev/sdc2 "${VAR_PATH}"
    mkdir -p "${LOG_PATH}"
    mount -t xfs /dev/sdc3 "${LOG_PATH}"
    mkdir -p "${DOCKER_PATH}"
    mount -t xfs /dev/sdc4 "${DOCKER_PATH}"

    # ensure partitions are mounted during boot too
    {
        echo "/dev/sdc1 ${HOME_PATH} xfs defaults 0 0"
        echo "/dev/sdc2 ${VAR_PATH} xfs defaults 0 0"
        echo "/dev/sdc3 ${LOG_PATH} xfs defaults 0 0"
        echo "/dev/sdc4 ${DOCKER_PATH} xfs defaults 0 0"
    } >> /etc/fstab
else
    echo 'WARN No suitable disk found for partitioning'
fi