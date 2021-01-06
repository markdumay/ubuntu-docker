#!/bin/sh
# Copyright 2020 Thomas Sjögren (konstruktoid)
# License: Apache License 2.0 (https://github.com/konstruktoid/hardening/blob/master/LICENSE)
# Source repository: https://github.com/konstruktoid/hardening/

# Adapted by Mark Dumay on January 6th, 2021. 

if lsblk | grep '^sdc.*5G'; then
    # store .ssh credentials of vagrant user somewhere safe
    mv /home/vagrant/.ssh /root/vagrant-ssh

    # create four primary partitions, allocating remaining disk space to Docker 
    sgdisk -n 1:0:+500MiB -t 1:8300 -c 1:log /dev/sdc
    sgdisk -n 2:0:+500MiB -t 2:8300 -c 2:audit /dev/sdc
    sgdisk -n 3:0:+500MiB -t 3:8300 -c 3:home /dev/sdc
    sgdisk -n 4:0:0       -t 4:8300 -c 4:docker /dev/sdc

    # format the four partitions
    mkfs.xfs /dev/sdc1
    mkfs.xfs /dev/sdc2
    mkfs.xfs /dev/sdc3
    mkfs.xfs /dev/sdc4

    # mount selected directories to new partitions
    mount -t xfs /dev/sdc1 /var/log
    mkdir -p /var/log/audit
    mount -t xfs /dev/sdc2 /var/log/audit
    mount -t xfs /dev/sdc3 /home
    mkdir -p /var/lib/docker
    mount -t xfs /dev/sdc4 /var/lib/docker

    # ensure partitions are mounted during boot too
    {
        echo '/dev/sdc1 /var/log xfs defaults 0 0'
        echo '/dev/sdc2 /var/log/audit xfs defaults 0 0'
        echo '/dev/sdc3 /home xfs defaults 0 0'
        echo '/dev/sdc4 /var/lib/docker xfs defaults 0 0'
    } >> /etc/fstab

    # restore .ssh credentials of vagrant user
    if grep '^vagrant' /etc/passwd; then
        mkdir -p /home/vagrant
        mv /root/vagrant-ssh /home/vagrant/.ssh
        chown -R vagrant:vagrant /home/vagrant
        chmod 0750 /home/vagrant
        chmod 0700 /home/vagrant/.ssh
        chmod 0600 /home/vagrant/.ssh/*
    fi
fi