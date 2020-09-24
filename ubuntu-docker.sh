#!/bin/bash

#======================================================================================================================
# Title         : ubuntu-docker.sh
# Description   : Installs Docker on a mint Ubuntu 20.04 LTS server
# Author        : Mark Dumay
# Date          : June 9th, 2020
# Version       : 0.1
# Usage         : sudo ./ubuntu-docker.sh [OPTIONS] COMMAND
# Repository    : https://github.com/markdumay/ubuntu-docker.git
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
DOWNLOAD_GITHUB=https://github.com/docker/compose
GITHUB_RELEASES=/docker/compose/releases/tag
PATH_DOCKER_BIN=/usr/local/bin
SSH_IP_ALLOW_FILENAME=/usr/local/sbin/ssh_ip_allow.sh
CRON_JOB="*/5 * * * * /bin/bash $SSH_IP_ALLOW_FILENAME"


#======================================================================================================================
# Variables
#======================================================================================================================
STEP=1
TOTAL_STEPS=1
COMMAND=''
ENABLE_PORTS='false'
FORCE='false'
TARGET_COMPOSE_VERSION=''
WORKING_DIR="$PWD"

#======================================================================================================================
# Helper Functions
#======================================================================================================================

# Display usage message
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo
    echo "Options:"
    echo "  -f, --force            Force update (bypass compatibility check)"
    echo "  -p, --ports            Open Docker Swarm ports (disabled by default)"
    echo
    echo "Commands:"
    echo "  init                   Initializes a mint Ubuntu 20.04 LTS installation"
    echo "  install                Installs Docker, Docker Compose, and Docker Swarm on a local Ubuntu 20.04 LTS host"
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

# Detects available versions for Docker Compose
detect_available_versions() {
    COMPOSE_TAGS=$(curl -s "$DOWNLOAD_GITHUB/tags" | egrep "a href=\"$GITHUB_RELEASES/[0-9]+.[0-9]+.[0-9]+\"")
    LATEST_COMPOSE_VERSION=$(echo "$COMPOSE_TAGS" | head -1 | cut -c 45- | sed "s/\">//g")
    TARGET_COMPOSE_VERSION=$LATEST_COMPOSE_VERSION

    # Test Docker Compose is available for download, exit otherwise
    if [ -z "$TARGET_COMPOSE_VERSION" ] ; then
        terminate "Could not find Docker Compose binaries for downloading"
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

        # reset existing machine id
        rm /etc/machine-id /var/lib/dbus/machine-id && systemd-machine-id-setup

        # install snap and livepatch
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
    ufw delete allow ssh > /dev/null

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

# Install Docker from the official Docker repository
execute_install_docker() {
    print_status "Install Docker from the official Docker repository"
    apt update -qq
    apt install -y apt-transport-https ca-certificates curl software-properties-common -qq
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
    apt update -qq
    apt-cache policy docker-ce > /dev/null
    apt install -y docker-ce -qq
}

# Add admin user to docker group
execute_add_admin() {
    print_status "Add $ADMIN_USER user to docker group"
    usermod -aG docker "$ADMIN_USER"
}

# Configure Docker daemon settings
execute_configure_docker_daemon() {
    print_status "Configure Docker daemon settings"
    cp daemon.json /etc/docker/daemon.json
    systemctl restart docker
}

# Enable auditing for Docker daemon and directories
execute_enable_docker_audit() {
    print_status "Enable auditing for Docker daemon and directories"
    apt-get -y install auditd -qq

    AUDIT="$(cat /etc/audit/rules.d/audit.rules | grep '/usr/bin/docker')"
    if [ -z "$AUDIT" ] ; then
        echo "-w /usr/bin/docker -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/dockerd -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /var/lib/docker -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/docker -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /lib/systemd/system/docker.service -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /lib/systemd/system/docker.socket -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/default/docker -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/docker/daemon.json -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/docker-containerd -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/containerd -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/docker-runc -p wa" | sudo tee -a /etc/audit/rules.d/audit.rules
    fi
    systemctl restart auditd
}

# Set DOCKER_CONTENT_TRUST environment setting
execute_docker_environment() {
    print_status "Set DOCKER_CONTENT_TRUST environment setting"
    echo "DOCKER_CONTENT_TRUST=1" | tee -a /etc/environment
}

# Download and install Docker Compose
execute_download_install_compose() {
    print_status "Downloading and installing Docker Compose ($TARGET_COMPOSE_VERSION)"
    COMPOSE_BIN="$DOWNLOAD_GITHUB/releases/download/$TARGET_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
    RESPONSE=$(curl -L "$COMPOSE_BIN" --write-out %{http_code} -o "$WORKING_DIR/docker-compose")
    if [ "$RESPONSE" != 200 ] ; then 
        terminate "Binary could not be downloaded"
    fi

    cp "$WORKING_DIR"/docker-compose "$PATH_DOCKER_BIN"/docker-compose
    chmod +x "$PATH_DOCKER_BIN"/docker-compose
}

# Initialize Docker Swarm
execute_docker_swarm() {
    print_status "Initializing Docker Swarm"
    SWARM="$(docker info | grep -c 'Swarm: active')"
    if [ ! "$SWARM" == '1' ] ; then
        PUBLIC_IP=$"(curl https://ipinfo.io/ip)"
        docker swarm init --advertise-addr "$PUBLIC_IP" --listen-addr "$PUBLIC_IP"
    else
        echo "Skipped, Docker Swarm already active"
    fi
}

# Configure Docker Swarm Ports (including Docker Machine)
execute_configure_swarm_ports() {
    print_status "Configuring Docker Swarm Ports"
    if [ "$ENABLE_PORTS" == 'true' ] ; then
        ufw allow 2376/tcp > /dev/null  # Docker Machine
        ufw allow 2377/tcp > /dev/null  # Docker Swarm Nodes
        ufw allow 7946/tcp > /dev/null  # Container network discovery
        ufw allow 7946/udp > /dev/null  # Container network discovery
        ufw allow 4789/udp > /dev/null  # Overlay network traffic
    else
        ufw delete allow 2376/tcp > /dev/null  # Docker Machine
        ufw delete allow 2377/tcp > /dev/null  # Docker Swarm Nodes
        ufw delete allow 7946/tcp > /dev/null  # Container network discovery
        ufw delete allow 7946/udp > /dev/null  # Container network discovery
        ufw delete allow 4789/udp > /dev/null  # Overlay network traffic
    fi

    ufw reload
    systemctl restart docker
}

#======================================================================================================================
# Main Script
#======================================================================================================================

# Show header
echo "Install Docker and Docker Swarm on Ubuntu 20.04 LTS"
echo 

# Test if script has root privileges, exit otherwise
if [ $(id -u) -ne 0 ] ; then
    usage
    terminate "You need to be root to run this script"
fi

# Process and validate command-line arguments
while [ "$1" != "" ] ; do
    case "$1" in
        -p | --ports )
            ENABLE_PORTS='true'
            ;;
        -f | --force )
            FORCE='true'
            ;;
        -h | --help )
            usage
            exit
            ;;
        init | install )
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
    install )
        TOTAL_STEPS=8
        validate_current_version
        detect_available_versions
        init_env_variables
        execute_install_docker
        execute_add_admin
        execute_configure_docker_daemon
        execute_enable_docker_audit
        execute_docker_environment
        execute_download_install_compose
        execute_docker_swarm
        execute_configure_swarm_ports
        ;;
    * )
        usage
        terminate "No command specified"
esac

# Display final message
if [ "$COMMAND" == 'install' ] ; then
    echo -e "\nDocker configuration done, validate with docker-bench-security:"
    echo "git clone https://github.com/docker/docker-bench-security.git"
    echo "cd docker-bench-security"
    echo "sudo ./docker-bench-security.sh"
else
    echo "Done."
fi