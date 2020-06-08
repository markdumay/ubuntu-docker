#!/bin/sh

#======================================================================================================================
# Title         : ubuntu-secure.sh
# Description   : Initializes a mint Ubuntu 18.04 LTS installation
# Author        : Mark Dumay
# Date          : June 8th, 2020
# Version       : 0.1
# Usage         : sudo ./ubuntu-secure.sh [OPTIONS] COMMAND
# Repository    : 
# Comments      : 
#======================================================================================================================

#======================================================================================================================
# Constants
#======================================================================================================================
RED='\033[0;31m' # Red color
GREEN='\033[0;32m' # Green color
NC='\033[0m' # No Color
BOLD='\033[1m' #Bold color
SUPPORTED_VERSION=bionic
ADMIN_USER=admin
CRON_SCHEDULE='*/5 * * * *'
CRON_JOB='$CRON_SCHEDULE /bin/bash $SSH_IP_ALLOW_FILENAME'
SSH_IP_ALLOW_FILENAME=/usr/local/sbin/ssh_ip_allow.sh
SSH_IP_ALLOW="
NEW_IP=$(dig ""$IP_SSH_ALLOW_HOSTNAME"" +short | tail -n 1)
OLD_IP=$(/usr/sbin/ufw status | grep ""$IP_SSH_ALLOW_HOSTNAME"" | head -n1 | tr -s ' ' | cut -f3 -d ' ')

if [ ""$$NEW_IP"" == ""$$OLD_IP"" ]; then
    echo IP address has not changed
else
    if [ -n ""$$OLD_IP"" ] ; then
        /usr/sbin/ufw delete allow from ""$$OLD_IP"" to any port ""$IP_SSH_PORT""
    fi
    /usr/sbin/ufw allow from ""$$NEW_IP"" to any port ""$IP_SSH_PORT"" comment ""$IP_SSH_ALLOW_HOSTNAME""
    echo iptables have been updated
fi
"


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
    echo "  init                   Initializes a mint Ubuntu 18.04 LTS installation"
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
    echo -e "${BOLD}Step $((STEP++)) from $TOTAL_STEPS: $1${NC}"
}

# Validate host is Ubuntu 18.04 (bionic beaver)
validate_current_version() {
    if [ "$FORCE" != 'true' ]; then
        ACTUAL_VERSION="$(cat /etc/os-release | grep '^VERSION_CODENAME' | cut -d'=' -f2)"
        if [ "$ACTUAL_VERSION" != "$SUPPORTED_VERSION" ]; then
            terminate "This script supports Ubuntu 18.04 only, use --force to override"
        fi
    fi
}

# Initialize environment variables from .env
init_env_variables() {
    source .env
    export $(cut -d= -f1 .env)

    # Set SSH port to default 22 if not specified
    if [ -z "$IP_SSH_PORT" ]; then
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
    if [ "$USER_NOT_EXISTS" == 1 ]; then
        adduser --quiet --gecos "" $ADMIN_USER
        usermod -aG sudo $ADMIN_USER
    fi
}

# Disable remote root login & SSH password authentication
execute_disable_remote_root() {}
    print_status "Disable remote root login & SSH password authentication"

    sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
    #sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
    service ssh restart
}

# Secure Shared Memory
execute_secure_memory() {}
    print_status "Secure Shared Memory"

    SHM="$(cat /etc/fstab | grep '/run/shm')"
    if [ ! "$SHM" ]; then
        echo 'none /run/shm tmpfs defaults,ro 0 0' >> /etc/fstab
    fi
}

# Make /boot read-only
execute_make_boot_read_only() {
    print_status "Make /boot read-only"

    BOOT="$(cat /etc/fstab | grep 'LABEL=/boot') "
    if [ ! "$BOOT" ]; then
        echo 'LABEL=/boot /boot ext2 defaults, ro 1 2' >> /etc/fstab
    fi
}

# Install Fail2ban
execute_install_fail2ban() {
    print_status "Install Fail2ban"

    apt-get install fail2ban > /dev/null 2>&1
}

# Install Canonical Livepatch
execute_install_livepatch() {
    print_status "Install Canonical Livepatch"

    if [ -z "$CANONICAL_TOKEN" ]; then
        export PATH="$PATH:/snap/bin"  # add manually to /etc/environment
        apt-get install snapd
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
    if [ "$IPV6" != 'true' ]; then
        sed -i 's/IPV6=yes/IPV6=no/g' /etc/default/ufw  
    fi

    # schedule cronjob to restrict SSH to a dynamic IP address if hostname is specified, else allow SSH from all IP addresses
    if [ ! -z "$IP_SSH_ALLOW_HOSTNAME" ]; then
        # install cron job
        printf "$SSH_IP_ALLOW" > "$SSH_IP_ALLOW_FILENAME"
        chmod +x "$SSH_IP_ALLOW_FILENAME"
        ! (crontab -l | grep -q "$SSH_IP_ALLOW_FILENAME") && (crontab -l; 
        echo "$CRON_JOB > /dev/null 2>&1 >> /var/log/ssh_allow.log 2>&1") | crontab -

        # install log rotate
        apt-get install logrotate > /dev/null 2>&1
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
echo "Initialize Ubuntu 18.04 LTS installation"
echo 

# Test if script has root privileges, exit otherwise
if [ $(id -u) -ne 0 ]; then 
    usage
    terminate "You need to be root to run this script"
fi

# Process and validate command-line arguments
while [ "$1" != "" ]; do
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