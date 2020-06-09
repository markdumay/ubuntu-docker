#!/bin/bash

#======================================================================================================================
# Title         : ubuntu-secure.sh
# Description   : Initializes a mint Ubuntu 20.04 LTS installation
# Author        : Mark Dumay
# Date          : June 9th, 2020
# Version       : 0.1
# Usage         : sudo ./ubuntu-secure.sh [OPTIONS] COMMAND
# Repository    : https://github.com/markdumay/ubuntu-secure.git
# Comments      : 
#======================================================================================================================

#======================================================================================================================
# Constants
#======================================================================================================================
RED='\033[0;31m' # Red color
GREEN='\033[0;32m' # Green color
NC='\033[0m' # No Color
BOLD='\033[1m' #Bold color
SUPPORTED_VERSION=focal
ADMIN_USER=admin
SSH_IP_ALLOW_FILENAME=/usr/local/sbin/ssh_ip_allow.sh
CRON_JOB="*/5 * * * * /bin/bash $SSH_IP_ALLOW_FILENAME"


#======================================================================================================================
# Variables
#======================================================================================================================
STEP=1
TOTAL_STEPS=1
COMMAND=''


#======================================================================================================================
# Helper Functions
#======================================================================================================================

# Display usage message
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo
    echo "Options:"
    echo "  -f, --force            Force update (bypass compatibility check)"
    echo
    echo "Commands:"
    echo "  init                   Initializes a mint Ubuntu 20.04 LTS installation"
    echo
}

# Display error message and terminate with non-zero error
terminate() {
    echo -e "${RED}${BOLD}ERROR: $1${NC}"
    echo
    exit 1
}

# Prints current progress to the console
print_status () {
    echo -e "${BOLD}Step $STEP from $TOTAL_STEPS: $1${NC}"
    STEP=$(( $STEP + 1 ))
}

# Validate host is Ubuntu 20.04 (focal fossa)
validate_current_version() {
    if [ "$FORCE" != 'true' ] ; then
        ACTUAL_VERSION="$(cat /etc/os-release | grep '^VERSION_CODENAME' | cut -d'=' -f2)"
        if [ "$ACTUAL_VERSION" != "$SUPPORTED_VERSION" ] ; then
            terminate "This script supports Ubuntu 20.04 only, use --force to override"
        fi
    fi
}

# Initialize environment variables from .env
init_env_variables() {
    set -a
    . ./.env
    set +a

    # Set SSH port to default 22 if not specified
    if [ -z "$IP_SSH_PORT" ] ; then
        IP_SSH_PORT=22
    fi
}

#======================================================================================================================
# Workflow Functions
#======================================================================================================================

# Create a non-root user with sudo privileges
execute_create_admin_user() {
    print_status "Create a non-root user with sudo privileges"

    USER_NOT_EXISTS="$(id -u $ADMIN_USER > /dev/null 2>&1; echo $?)"
    if [ "$USER_NOT_EXISTS" == 1 ] ; then
        adduser --quiet --gecos "" $ADMIN_USER
        usermod -aG sudo $ADMIN_USER
    else
        echo "Skipped, user already exists"
    fi
}

# Disable remote root login
execute_disable_remote_root() {
    print_status "Disable remote root login"

    PERMIT_ROOT_LOGIN=$(cat /etc/ssh/sshd_config | grep "PermitRootLogin yes")

    if [ ! -z "$PERMIT_ROOT_LOGIN" ] ; then
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
        # TODO: consider disabling SSH password authentication
        #sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
        service ssh restart
    else
        echo "Skipped, root login already disabled"
    fi
}

# Secure Shared Memory
execute_secure_memory() {
    print_status "Secure Shared Memory"

    SHM="$(cat /etc/fstab | grep '/run/shm')"
    if [ ! "$SHM" ] ; then
        echo 'none /run/shm tmpfs defaults,ro 0 0' >> /etc/fstab
    else
        echo "Skipped, shared memory already configured"
    fi
}

# Make /boot read-only
execute_make_boot_read_only() {
    print_status "Make /boot read-only"

    BOOT="$(cat /etc/fstab | grep 'LABEL=/boot') "
    if [ ! "$BOOT" ] ; then
        echo 'LABEL=/boot /boot ext2 defaults, ro 1 2' >> /etc/fstab
    else
        echo "Skipped, /boot already configured"
    fi
}

# Install Fail2ban
execute_install_fail2ban() {
    print_status "Install Fail2ban"

    apt-get install -y fail2ban > /dev/null 2>&1
}

# Install Canonical Livepatch
execute_install_livepatch() {
    print_status "Install Canonical Livepatch"

    if [ ! -z "$CANONICAL_TOKEN" ] ; then
        export PATH="$PATH:/snap/bin"  # add manually to /etc/environment
        apt-get install -y snapd > /dev/null 2>&1
        snap install canonical-livepatch
        canonical-livepatch enable "$CANONICAL_TOKEN"
    else
        echo "Skipped, 'CANONICAL_TOKEN' not specified"
    fi
}

# Configure and enable firewall
execute_install_firewall() {
    print_status "Configure and enable firewall"

    # enable http (port 80) and https traffic (port 443)
    ufw allow http > /dev/null
    ufw allow https > /dev/null

    # disable IPv6 traffic if specified
    if [ "$IPV6" != 'true' ] ; then
        sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw
    fi

    # schedule cronjob to restrict SSH to a dynamic IP address if specified, else allow SSH from all IP addresses
    if [ ! -z "$IP_SSH_ALLOW_HOSTNAME" ] ; then
        # install cron job
        cp ssh_ip_allow.sh "$SSH_IP_ALLOW_FILENAME"
        chmod +x "$SSH_IP_ALLOW_FILENAME"
        sed -i "s/{IP_SSH_ALLOW_HOSTNAME}/$IP_SSH_ALLOW_HOSTNAME/g" "$SSH_IP_ALLOW_FILENAME"
        sed -i "s/{IP_SSH_PORT}/$IP_SSH_PORT/g" "$SSH_IP_ALLOW_FILENAME"
        ! (crontab -l | grep -q "$SSH_IP_ALLOW_FILENAME") && 
        (crontab -l; echo "$CRON_JOB > /dev/null 2>&1 >> /var/log/ssh_allow.log 2>&1") | crontab -

        # execute cron job immediately to only allow ssh from specified IP address
        sudo ufw delete allow ssh
        /bin/bash "$SSH_IP_ALLOW_FILENAME"

        # install log rotate
        apt-get install -y logrotate > /dev/null 2>&1
        cp ssh_allowlog /etc/logrotate.d/ssh_allowlog
        chmod 644 /etc/logrotate.d/ssh_allowlog && chown root:root /etc/logrotate.d/ssh_allowlog
    else
        ufw allow ssh > /dev/null
    fi

    # restart the firewall to effectuate the changes (this might disrupt your current ssh sesion)
    ufw disable && ufw enable
}

#======================================================================================================================
# Main Script
#======================================================================================================================

# Show header
echo "Initialize Ubuntu 20.04 LTS installation"
echo 

# Test if script has root privileges, exit otherwise
if [ $(id -u) -ne 0 ] ; then
    usage
    terminate "You need to be root to run this script"
fi

# Process and validate command-line arguments
while [ "$1" != "" ] ; do
    case "$1" in
        -f | --force )
            FORCE='true'
            ;;
        -h | --help )
            usage
            exit
            ;;
        init )
            COMMAND="$1"
            ;;
        * )
            usage
            terminate "Unrecognized parameter ($1)"
    esac
    shift
done

# Execute workflows
case "$COMMAND" in
    init )
        TOTAL_STEPS=7
        validate_current_version
        init_env_variables
        execute_create_admin_user
        execute_disable_remote_root
        execute_secure_memory
        execute_make_boot_read_only
        execute_install_fail2ban
        execute_install_livepatch
        execute_install_firewall
        ;;
    * )
        usage
        terminate "No command specified"
esac

echo "Done."