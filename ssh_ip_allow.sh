#!/bin/bash

#======================================================================================================================
# Title         : ssh_ip_allow.sh
# Description   : Restrict SSH access to a dynamic IP address
# Author        : Mark Dumay
# Date          : September 24th, 2020
# Version       : 0.2
# Usage         : sudo ./ssh_ip_allow.sh
# Repository    : https://github.com/markdumay/ubuntu-docker.git
# Comments      : Used by ubuntu-docker.sh
#======================================================================================================================

#======================================================================================================================
# Constants
#======================================================================================================================
IP_SSH_ALLOW_HOSTNAME={IP_SSH_ALLOW_HOSTNAME}
IP_SSH_PORT={IP_SSH_PORT}


#======================================================================================================================
# Variables
#======================================================================================================================
NEW_IP=$(dig "$IP_SSH_ALLOW_HOSTNAME" +short | tail -n 1)
OLD_IP=$(/usr/sbin/ufw status | grep "$IP_SSH_ALLOW_HOSTNAME" | head -n1 | tr -s ' ' | cut -f3 -d ' ')
LOG_PREFIX="[$(date --rfc-3339=seconds)] [SSH_IP_ALLOW] "


#======================================================================================================================
# Helper Functions
#======================================================================================================================
# Prints current progress to the console in normal or logging format
log() {
    echo "${LOG_PREFIX}$1"
}

#======================================================================================================================
# Main Script
#======================================================================================================================
if [ "$NEW_IP" == "$OLD_IP" ] ; then
    log 'IP address has not changed'
else
    if [ -n "$OLD_IP" ] ; then
        /usr/sbin/ufw delete allow from "$OLD_IP" to any port "$IP_SSH_PORT"
    fi
    /usr/sbin/ufw allow from "$NEW_IP" to any port "$IP_SSH_PORT" comment "$IP_SSH_ALLOW_HOSTNAME"
    log 'iptables have been updated'
fi
