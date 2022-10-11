#!/bin/sh

#======================================================================================================================
# Title         : partition.sh
# Description   : Partition and mount the (virtual) disk of a server running Ubuntu 22.04 LTS
# Author        : Mark Dumay
# Date          : October 11th, 2022
# Version       : 0.6.0
# Usage         : partition.sh execute [DISK] [SIZE]
# Repository    : https://github.com/markdumay/ubuntu-docker.git
# License       : MIT - https://github.com/markdumay/ubuntu-docker/blob/master/LICENSE
# Credits       : Inspired by Hardening repository from Thomas Sjögren (https://github.com/konstruktoid/hardening/)
# Comments      : Portions copyrighted by Thomas Sjögren (konstruktoid), with Apache License 2.0
#======================================================================================================================


#======================================================================================================================
# This script creates the partitions of a (virtual) disk drive that is part of a server running Ubuntu. It has been
# tested with Ubuntu 22.04 LTS (Jammy Jellyfish). The script aborts if no compatible drive is found. The (virtual)
# drive is reformatted, so any existing data is lost. The script creates four partitions that act as mount point for
# the following directories:
# PARTITION SIZE        MOUNT POINT
# --------- ----        -----------
# /dev/vdb1   500MiB    /home
# /dev/vdb2 1.000MiB    /var
# /dev/vdb3   500MiB    /var/log
# /dev/vdb4 3.000MiB    /var/lib/docker
#
# This script is based on an example developed by Thomas Sjögren (konstruktoid), whom also authored an Ansible playbook
# for the hardening of several Linux distributions, including Ubuntu. He is also the editor of the Docker Bench for
# Security.
#======================================================================================================================

#======================================================================================================================
# Constants
#======================================================================================================================
readonly RED='\e[31m' # Red color
readonly NC='\e[m' # No color / reset
readonly BOLD='\e[1m' # Bold font
readonly HOME_PATH='/home'
readonly VAR_PATH='/var'
readonly LOG_PATH='/var/log'
readonly DOCKER_PATH='/var/lib/docker'


#======================================================================================================================
# Variables
#======================================================================================================================
command=''
disk_name=''
disk_size=''
force='false'
step=0
total_steps=0


#======================================================================================================================
# Helper Functions
#======================================================================================================================

#======================================================================================================================
# Prompts the user to confirm the operation, unless forced.
#======================================================================================================================
# Globals:
#   - force
# Outputs:
#   Terminates with zero exit code if user does not confirm the operation.
#======================================================================================================================
confirm_operation() {
    if [ "${force}" != 'true' ] ; then
        echo
        echo "WARNING! This will format drive '${disk_name}' and recreate the following mount points:"
        echo " - ${HOME_PATH}"
        echo " - ${VAR_PATH}"
        echo " - ${LOG_PATH}"
        echo " - ${DOCKER_PATH}"
        echo

        while true; do
            printf "Are you sure you want to continue? [y/N] "
            read -r yn
            yn=$(echo "${yn}" | tr '[:upper:]' '[:lower:]')

            case "${yn}" in
                y | yes )     break;;
                n | no | "" ) exit;;
                * )           echo "Please answer y(es) or n(o)";;
            esac
        done
    fi
}

#======================================================================================================================
# Print current progress to the console and shows progress against total number of steps.
#======================================================================================================================
# Arguments:
#   $1 - Progress message to display.
# Outputs:
#   Writes message to stdout.
#======================================================================================================================
print_status() {
    step=$((step + 1))
    printf "${BOLD}%s${NC}\n" "Step ${step} from ${total_steps}: $1"
}

#======================================================================================================================
# Displays error message on console and terminates with non-zero error.
#======================================================================================================================
# Arguments:
#   $1 - Error message to display.
# Outputs:
#   Writes error message to stderr, non-zero exit code.
#======================================================================================================================
terminate() {
    printf "${RED}${BOLD}%s${NC}\n" "ERROR: $1"
    exit 1
}

#======================================================================================================================
# Display usage message.
#======================================================================================================================
# Outputs:
#   Writes message to stdout.
#======================================================================================================================
usage() { 
    echo "This script creates the partitions of a (virtual) disk drive that is part of a"
    echo "server running Ubuntu. It has been tested with Ubuntu 22.04 LTS (Jammy"
    echo "Jellyfish). The script aborts if no compatible drive is found. The virtual"
    echo "drive is reformatted, so any existing data is lost. The script creates four"
    echo "partitions that act as mount point for the following directories:"
    echo "PARTITION SIZE        MOUNT POINT"
    echo "--------- ----        -----------"
    echo "/dev/vdb1   500MiB    /home"
    echo "/dev/vdb2 1.000MiB    /var"
    echo "/dev/vdb3   500MiB    /var/log"
    echo "/dev/vdb4 3.000MiB    /var/lib/docker"
    echo
    echo
    echo "Usage: $0 [OPTIONS] COMMAND" 
    echo
    echo "Options:"
    echo "  -f, --force            Force execution, bypasses validation and confirmation"
    echo "  -h, --help             Display this help"
    echo
    echo "Commands:"
    echo "  execute [DISK] [SIZE]  Format, partition, and mount folders of drive DISK of SIZE"
    echo
    echo "Example:"
    echo "  sudo $0 execute vdb 5G"
    echo
}

#======================================================================================================================
# Validates if the specified drive exists.
#======================================================================================================================
# Globals:
#   - force
# Outputs:
#   Terminates with zero exit code if drive of specified size is not found.
#======================================================================================================================
validate_drive() {
    (lsblk | grep -q "^${disk_name}.*${disk_size}") || terminate "Disk '${disk_name}' of size '${disk_size}' not found"
}

#======================================================================================================================
# Validates if the folders are not already mounted to the specified drive.
#======================================================================================================================
# Globals:
#   - force
# Outputs:
#   Terminates with zero exit code if one or more mount points already exist.
#======================================================================================================================
validate_mounts() {
    (mount -l | grep -q "/dev/${disk_name}1 on ${HOME_PATH}") && terminate "Folder already mounted: ${HOME_PATH}"
    (mount -l | grep -q "/dev/${disk_name}2 on ${VAR_PATH}") && terminate "Folder already mounted: ${VAR_PATH}"
    (mount -l | grep -q "/dev/${disk_name}3 on ${LOG_PATH}") && terminate "Folder already mounted: ${LOG_PATH}"
    (mount -l | grep -q "/dev/${disk_name}4 on ${DOCKER_PATH}") && terminate "Folder already mounted: ${DOCKER_PATH}"
}

#======================================================================================================================
# Validates if script has root privileges and if rsync package is installed.
#======================================================================================================================
# Globals:
#   - force
# Outputs:
#   Terminates with zero exit code if prerequisites are not met.
#======================================================================================================================
validate_prerequisites() {
    # Test if script has root privileges, exit otherwise
    id=$(id -u)
    if [ "${id}" -ne 0 ]; then
        terminate "You need to be root to run this script"
    fi

    # Test if rsync package is available, exit otherwise
    which rsync > /dev/null || terminate "Package rsync not found, install with 'sudo apt install rsync'"
}


#======================================================================================================================
# Workflow Functions
#======================================================================================================================

#======================================================================================================================
# Creates four mount points and synchronizes them with existing data.
#======================================================================================================================
# Outputs:
#   Terminates with zero exit code if an error occurred.
#======================================================================================================================
create_mounts() {
    print_status 'Creating mount points'

    # create temporary mount points
    mkdir -p "/media/home"
    mount -t xfs "/dev/${disk_name}1" "/media/home" || terminate "Cannot create temp mount: /media/home"
    mkdir -p "/media/var"
    mount -t xfs "/dev/${disk_name}2" "/media/var" || terminate "Cannot create temp mount: /media/var"
    mkdir -p "/media/log"
    mount -t xfs "/dev/${disk_name}3" "/media/log" || terminate "Cannot create temp mount: /media/log"

    # copy current data to new partitions
    rsync -aXS "${HOME_PATH}/." "/media/home/." || terminate "Cannot copy data: /media/home"
    rsync -aXS "${VAR_PATH}/." --exclude 'log' "/media/var/." || terminate "Cannot copy data: /media/var"
    rsync -aXS "${LOG_PATH}/." "/media/log/." || terminate "Cannot copy data: /media/log"

    # remove obsolete directories
    rm -rf "${HOME_PATH}"
    rm -rf "${VAR_PATH}"

    # remove temporary mount points
    umount "/dev/${disk_name}1"
    umount "/dev/${disk_name}2"
    umount "/dev/${disk_name}3"

    # create final mount points
    mkdir -p "${HOME_PATH}"
    mount -t xfs "/dev/${disk_name}1" "${HOME_PATH}" || terminate "Cannot create mount: ${HOME_PATH}"
    mkdir -p "${VAR_PATH}"
    mount -t xfs "/dev/${disk_name}2" "${VAR_PATH}" || terminate "Cannot create mount: ${VAR_PATH}"
    mkdir -p "${LOG_PATH}"
    mount -t xfs "/dev/${disk_name}3" "${LOG_PATH}" || terminate "Cannot create mount: ${LOG_PATH}"
    mkdir -p "${DOCKER_PATH}"
    mount -t xfs "/dev/${disk_name}4" "${DOCKER_PATH}" || terminate "Cannot create mount: ${DOCKER_PATH}"
}

#======================================================================================================================
# Creates four primary partitions on the specified drive.
#======================================================================================================================
# Outputs:
#   Terminates with zero exit code if an error occurred.
#======================================================================================================================
create_partitions() {
    print_status 'Creating primary partitions'

    # create four primary partitions, allocating remaining disk space to Docker
    sgdisk -n 1:0:+500MiB  -t 1:8300 -c 1:home   "/dev/${disk_name}" || terminate "Cannot create partition: 1:home"
    sgdisk -n 2:0:+1000MiB -t 2:8300 -c 2:var    "/dev/${disk_name}" || terminate "Cannot create partition: 2:var"
    sgdisk -n 3:0:+500MiB  -t 3:8300 -c 3:log    "/dev/${disk_name}" || terminate "Cannot create partition: 3:log"
    sgdisk -n 4:0:0        -t 4:8300 -c 4:docker "/dev/${disk_name}" || terminate "Cannot create partition: 4:docker"

    # format the four partitions
    mkfs.xfs "/dev/${disk_name}1" || terminate "Cannot format partition: /dev/${disk_name}1"
    mkfs.xfs "/dev/${disk_name}2" || terminate "Cannot format partition: /dev/${disk_name}2"
    mkfs.xfs "/dev/${disk_name}3" || terminate "Cannot format partition: /dev/${disk_name}3"
    mkfs.xfs "/dev/${disk_name}4" || terminate "Cannot format partition: /dev/${disk_name}4"
}

#======================================================================================================================
# Ensures the folders are mounted during boot.
#======================================================================================================================
# Outputs:
#   Terminates with zero exit code if an error occurred.
#======================================================================================================================
update_boot_procedure() {
    print_status 'Updating boot procedure'

    # ensure partitions are mounted during boot too
    grep -q "${HOME_PATH}" < /etc/fstab || echo "/dev/${disk_name}1 ${HOME_PATH} xfs defaults 0 0" >> /etc/fstab
    grep -q "${VAR_PATH}" < /etc/fstab || echo "/dev/${disk_name}2 ${VAR_PATH} xfs defaults 0 0" >> /etc/fstab
    grep -q "${LOG_PATH}" < /etc/fstab || echo "/dev/${disk_name}3 ${LOG_PATH} xfs defaults 0 0" >> /etc/fstab
    grep -q "${DOCKER_PATH}" < /etc/fstab || echo "/dev/${disk_name}4 ${DOCKER_PATH} xfs defaults 0 0" >> /etc/fstab
}


#======================================================================================================================
# Main Script
#======================================================================================================================

#======================================================================================================================
# Entrypoint for the script.
#======================================================================================================================
main() {
    # Show header
    echo "Mount key folders to separate partitions"
    echo 

    # Process and validate command-line arguments
    while [ "$1" != "" ]; do
        case "$1" in
            -f | --force )
                force='true'
                ;;
            -h | --help )
                usage
                exit
                ;;
            execute )
                command="$1"
                [ "$#" -ne 3 ] && terminate 'Expected arguments [DISK] and [SIZE]'
                shift
                disk_name="$1"
                shift
                disk_size="$1"
                ;;
            * )
                terminate "Unrecognized parameter ($1)"
        esac
        shift
    done

    # Execute workflows
    case "${command}" in
        execute )
            total_steps=3
            validate_prerequisites
            validate_drive
            validate_mounts
            confirm_operation
            create_partitions
            create_mounts
            update_boot_procedure
            ;;
        * )
            usage
            terminate "No command specified"
    esac

    echo "Done."
}

main "$@"