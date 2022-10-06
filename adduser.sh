#!/bin/bash

#======================================================================================================================
# Title         : ubuntu-docker.sh
# Description   : Installs and hardens Docker on a Ubuntu 20.04 LTS host
# Author        : Mark Dumay
# Date          : October 13th, 2020
# Version       : 0.3
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

SUPPORTED_OS_VERSION=focal
ADMIN_USER=admin
DOWNLOAD_COMPOSE=https://github.com/docker/compose
GITHUB_RELEASES=/docker/compose/releases/tag
GITHUB_API_COMPOSE=https://api.github.com/repos/docker/compose/releases/latest
PATH_DOCKER_BIN=/usr/local/bin
PATH_DOCKER_DATA=/data/docker
SSH_IP_ALLOW_FILENAME=/usr/local/sbin/ssh_ip_allow.sh
CRON_JOB="*/5 * * * * /bin/bash $SSH_IP_ALLOW_FILENAME"


#======================================================================================================================
# Variables
#======================================================================================================================
STEP=0
TOTAL_STEPS=1
LOG_PREFIX=''
COMMAND=''
ENABLE_PORTS='false'
FORCE='false'
DOCKER_VERSION=''
COMPOSE_VERSION=''
TARGET_COMPOSE_VERSION=''
WORKING_DIR="$PWD"

#======================================================================================================================
# Helper Functions
#======================================================================================================================

# Display script header
show_header() {
    [ ! -z "$LOG_PREFIX" ] && return

    echo "Installs and hardens Docker on a Ubuntu 20.04 LTS host"
    echo
}

# Display usage message
usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo
    echo "Options:"
    echo "  -f, --force            Force update (bypass compatibility check)"
    echo "  -p, --ports            Open Docker Swarm ports (disabled by default)"
    echo
    echo "Commands:"
    echo "  host                   Hardens a mint Ubuntu 20.04 LTS host"
    echo "  install                Installs Docker, Docker Compose, and Docker Swarm on a local Ubuntu 20.04 LTS host"
    echo "  update                 Updates the Docker Engine and Docker Compose to the latest version"
    echo "  remove                 Removes an existing Docker and Docker Compose installation"
    echo
}

# Display error message and terminate with non-zero error
terminate() {
    echo -e "${RED}${BOLD}${LOG_PREFIX}ERROR: $1${NC}" 1>&2
    if [ ! -z "$PARAM_LOG_FILE" ] ; then
        echo "${LOG_PREFIX}ERROR: $1" >> "$PARAM_LOG_FILE"
    fi
    exit 1
}

# Prints current progress to the console
print_status() {
    ((STEP++))
    echo -e "${BOLD}${LOG_PREFIX}Step $STEP from $TOTAL_STEPS: $1${NC}"
    if [ ! -z "$PARAM_LOG_FILE" ] ; then
        echo "${LOG_PREFIX}Step $STEP from $TOTAL_STEPS: $1" >> "$PARAM_LOG_FILE"
    fi
}

# Prints current progress to the console in normal or logging format
log() {
    echo "${LOG_PREFIX}$1"
    if [ ! -z "$PARAM_LOG_FILE" ] ; then
        echo "${LOG_PREFIX}$1" >> "$PARAM_LOG_FILE"
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
    # Test Docker Compose is available for download, exit otherwise
    TARGET_COMPOSE_VERSION=$(curl -s "$GITHUB_API_COMPOSE" | grep "tag_name" | egrep -o "[0-9]+.[0-9]+.[0-9]+")
    if [ -z "$TARGET_COMPOSE_VERSION" ] ; then
        terminate "Could not find Docker Compose binaries for downloading"
    fi
}


# Validate host is Ubuntu 20.04 (focal fossa)
validate_host_version() {
    if [ "$OS_VERSION" != "$SUPPORTED_OS_VERSION" ] ; then
        terminate "This script supports Ubuntu 20.04 only, use --force to override"
    fi
}


#======================================================================================================================
# Workflow Functions
#======================================================================================================================

# Detects current versions for OS, Docker, and Docker Compose
detect_host_versions() {
    print_status "Validating host, Docker, and Docker Compose versions"

    # Detect current OS version
    OS_VERSION=$(cat /etc/os-release | grep '^VERSION_CODENAME' | cut -d'=' -f2)
    local OS_PRETTY_VERSION=$(cat /etc/os-release | grep '^PRETTY_NAME=' | cut -d'=' -f2)

    # Detect current Docker version
    DOCKER_VERSION=$(docker -v 2>/dev/null | egrep -o "[0-9]*.[0-9]*.[0-9]*," | cut -d',' -f 1)

    # Detect current Docker Compose version
    COMPOSE_VERSION=$(docker-compose -v 2>/dev/null | egrep -o "[0-9]*.[0-9]*.[0-9]*," | cut -d',' -f 1)

    log "Current OS: ${OS_PRETTY_VERSION:-Unknown}"
    log "Current Docker: ${DOCKER_VERSION:-Unknown}"
    log "Current Docker Compose: ${COMPOSE_VERSION:-Unknown}"
    if [ "$FORCE" != 'true' ] ; then
        validate_host_version
    fi
}

# Installs required packages
execute_install_packages() {
    local PACKAGES="snapd fail2ban logrotate auditd notary"
    print_status "Install packages: $PACKAGES"
    apt-get install -y "$PACKAGES" > /dev/null 2>&1
}

# Create a non-root user with sudo privileges
execute_create_admin_user() {
    print_status "Create a non-root user with sudo privileges"

    if ! id -u "$ADMIN_USER" > /dev/null 2>&1 ; then
        adduser --quiet --gecos "" "$ADMIN_USER"
        usermod -aG sudo "$ADMIN_USER"
    else
        log "Skipped, user already exists"
    fi
}

# Disable remote root login
execute_disable_remote_root() {
    print_status "Disable remote root login"

    if cat /etc/ssh/sshd_config | grep -q "PermitRootLogin yes" ; then
        sed -i 's/PermitRootLogin yes/PermitRootLogin no/g' /etc/ssh/sshd_config
        service ssh restart
    else
        log "Skipped, root login already disabled"
    fi
}

# Secure Shared Memory
execute_secure_memory() {
    print_status "Secure Shared Memory"

    if ! cat /etc/fstab | grep -q '/run/shm' ; then
        echo 'none /run/shm tmpfs defaults,ro 0 0' >> /etc/fstab
    else
        log "Skipped, shared memory already configured"
    fi
}

# Make /boot read-only
execute_make_boot_read_only() {
    print_status "Make /boot read-only"

    if ! cat /etc/fstab | grep -q 'LABEL=/boot' ; then
        echo 'LABEL=/boot /boot ext2 defaults, ro 1 2' >> /etc/fstab
    else
        log "Skipped, /boot already configured"
    fi
}

# Install Canonical Livepatch
execute_install_livepatch() {
    print_status "Install Canonical Livepatch"

    if [ ! -z "$CANONICAL_TOKEN" ] ; then
        local STATUS=$(systemctl | grep /run/snapd/ns/canonical-livepatch.mnt | grep -o active)
        if [ "$STATUS" != 'active' ] ; then
            export PATH="$PATH:/snap/bin"  # add manually to /etc/environment

            # reset existing machine id
            rm /etc/machine-id /var/lib/dbus/machine-id > /dev/null 2>&1 ; dbus-uuidgen --ensure=/etc/machine-id

            # install livepatch with snap
            snap install canonical-livepatch
            canonical-livepatch enable "$CANONICAL_TOKEN"
        else
            log "Skipped, Canonical Livepatch already installed"
        fi
    else
        echo "Skipped, 'CANONICAL_TOKEN' not specified"
    fi
}

# Enable swap limit support
execute_enable_swap_limit() {
    print_status "Enable swap limit support"

    local CONFIG='GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"'
    if ! cat /etc/default/grub | grep -q "$CONFIG" ; then
        echo "$CONFIG" >> /etc/default/grub
        update-grub
    else   
        log "Skipped, swap limiting already enabled"
    fi
}

# Create Docker mount point
execute_create_docker_mount() {
    print_status "Create Docker mount point"

    if [ ! -z "$PARTITION"  ] ; then
        if [ ! -d "$PATH_DOCKER_DATA" ] ; then
            # identify UUID and TYPE for partition
            local UUID=$(blkid "$PARTITION" | grep -oP 'UUID=\K.*' | xargs | awk '{print $1}')
            local TYPE=$(blkid "$PARTITION" | grep -oP 'TYPE=\K.*' | xargs | awk '{print $1}')

            # ensure the partition is mounted at boot
            cp /etc/fstab /etc/fstab.$(date +%Y-%m-%d)
            echo "UUID=$UUID $PATH_DOCKER_DATA           $TYPE    defaults        0       2" >> /etc/fstab

            # create and mount the Docker data folder to the partition
            mkdir -p "$PATH_DOCKER_DATA"
            mount -a
        else
            log "Skipped, Docker directory already exists"
        fi
    else
        log "Skipped, Docker partition not specified"
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

        # configure log rotate
        cp ssh_allowlog /etc/logrotate.d/ssh_allowlog
        chmod 644 /etc/logrotate.d/ssh_allowlog && chown root:root /etc/logrotate.d/ssh_allowlog
    else
        ufw allow ssh > /dev/null
    fi

    # restart the firewall to effectuate the changes (this might disrupt your current ssh sesion)
    ufw disable && ufw enable
}

# Install Docker from the official Docker repository
# Source: https://docs-stage.docker.com/engine/install/ubuntu/
execute_install_docker() {
    print_status "Install Docker from the official Docker repository"
    
    # Set up the repository
    apt update -qq
    apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common -qq
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    local FINGERPRINT=$(apt-key fingerprint '0EBFCD88' | grep 'Docker Release (CE deb)')
    [ -z "$FINGERPRINT" ] && terminate "Unknown Docker fingerprint"

    local ARCH=$(arch | sed 's/x86_64/amd64/g')
    add-apt-repository "deb [arch=$ARCH] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

    # Install Docker CE engine
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io
}

# Add admin user to docker group
execute_add_admin() {
    print_status "Add $ADMIN_USER user to docker group"
    usermod -aG docker "$ADMIN_USER"
}

# Configure dockernotary alias
#TODO: update notary
execute_configure_notary() {
    print_status "Configure dockernotary alias"
    alias dockernotary="notary -s https://notary.docker.io -d ~/.docker/trust"    
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

    # local AUDIT=$(cat /etc/audit/rules.d/audit.rules | grep '/usr/bin/docker')
    # if [ -z "$AUDIT" ] ; then
    if ! cat /etc/audit/rules.d/audit.rules | grep -q '/usr/bin/docker' ; then
        echo "-w /usr/bin/docker -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/dockerd -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /var/lib/docker -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/docker -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /lib/systemd/system/docker.service -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /lib/systemd/system/docker.socket -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/default/docker -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /etc/docker/daemon.json -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/docker-containerd -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/containerd -p wa" | tee -a /etc/audit/rules.d/audit.rules
        echo "-w /usr/bin/docker-runc -p wa" | tee -a /etc/audit/rules.d/audit.rules
    fi
    systemctl restart auditd
}

# Set DOCKER_CONTENT_TRUST environment setting
execute_docker_environment() {
    print_status "Set DOCKER_CONTENT_TRUST environment setting"

    if ! cat /etc/environment | grep -q 'DOCKER_CONTENT_TRUST' ; then
        echo "DOCKER_CONTENT_TRUST=1" | tee -a /etc/environment
    fi
}

# Download and install Docker Compose
execute_download_install_compose() {
    print_status "Downloading and installing Docker Compose ($TARGET_COMPOSE_VERSION)"
    local COMPOSE_BIN="$DOWNLOAD_COMPOSE/releases/download/$TARGET_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
    local RESPONSE=$(curl -L "$COMPOSE_BIN" --write-out %{http_code} -o "$WORKING_DIR/docker-compose")
    if [ "$RESPONSE" != 200 ] ; then 
        terminate "Binary could not be downloaded"
    fi

    cp "$WORKING_DIR"/docker-compose "$PATH_DOCKER_BIN"/docker-compose
    chmod +x "$PATH_DOCKER_BIN"/docker-compose
}


# TODO: change /lib/systemd/system/docker.service (remove -H)
# 1. Create certificates
    # execute_configure_docker_ssl()
    # copy to /etc/docker/DOMAIN/
# 2. Update daemon.json
# 3. Update docker.service
    # ExecStart=/usr/bin/dockerd --containerd=/run/containerd/containerd.sock
# 4. Restart Docker
    # systemctl daemon-reload
    # systemctl restart docker
    # systemctl enable docker

# Source: https://docs.docker.com/engine/security/https/
# use instead? https://gist.github.com/kekru/974e40bb1cd4b947a53cca5ba4b0bbe5
# execute_configure_docker_ssl() {
#     local HOST_FQDN='vmi310111.contaboserver.net' # TODO: temp
#     local HOST_IP='173.249.42.213' # TPDP: temp
#     openssl genrsa -aes256 -out ca-key.pem 4096
#     openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -out ca.pem
#     openssl genrsa -out server-key.pem 4096
#     openssl req -subj "/CN=$HOST_FQDN" -sha256 -new -key server-key.pem -out server.csr
#     echo "subjectAltName = DNS:$HOST_FQDN,IP:$HOST_IP,IP:127.0.0.1" >> extfile.cnf
#     echo extendedKeyUsage = serverAuth >> extfile.cnf
#     openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
#         -CAcreateserial -out server-cert.pem -extfile extfile.cnf
#     openssl genrsa -out key.pem 4096
#     openssl req -subj '/CN=client' -new -key key.pem -out client.csr
#     echo extendedKeyUsage = clientAuth > extfile-client.cnf
#     openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
#         -CAcreateserial -out cert.pem -extfile extfile-client.cnf
#     rm -v client.csr server.csr extfile.cnf extfile-client.cnf
#     chmod -v 0400 ca-key.pem key.pem server-key.pem
#     chmod -v 0444 ca.pem server-cert.pem cert.pem

#     # copy server certificates
#     mkdir -pv /var/docker
#     cp -v {ca,server-cert,server-key}.pem /var/docker

#     # copy client certificates
#     mkdir -pv ~/.docker
#     cp -v {ca,cert,key}.pem ~/.docker
#     export DOCKER_HOST="tcp://$HOST_FQDN:2376"
#     export DOCKER_TLS_VERIFY=1
# }

# Initialize Docker Swarm
execute_docker_swarm() {
    print_status "Initializing Docker Swarm"
    if ! docker info | grep -q 'Swarm: active' ; then
        local PUBLIC_IP=$(curl https://ipinfo.io/ip)
        docker swarm init --advertise-addr "$PUBLIC_IP" --listen-addr "$PUBLIC_IP"
    else
        log "Skipped, Docker Swarm already active"
    fi
}

# Encrypts application data traffic for default Swarm overlay network
execute_encrypt_ingress() {
    print_status "Recreating ingress network to enable encryption"

    # TODO: fix error "Error response from daemon: network with name ingress already exists"
    yes | docker network rm ingress
    docker network create --driver overlay --opt encrypted --ingress ingress
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
show_header

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
        -p | --ports )
            ENABLE_PORTS='true'
            ;;
        host | install )
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
    host )
        TOTAL_STEPS=9
        validate_current_version
        init_env_variables
        execute_install_packages
        execute_create_admin_user
        execute_disable_remote_root
        execute_secure_memory
        execute_make_boot_read_only
        execute_install_livepatch
        execute_enable_swap_limit
        execute_install_firewall
        ;;
    install )
        TOTAL_STEPS=11
        validate_current_version
        detect_available_versions
        init_env_variables
        execute_create_docker_mount
        execute_install_docker
        execute_add_admin
        execute_configure_notary
        execute_configure_docker_daemon
        execute_enable_docker_audit
        execute_docker_environment
        execute_download_install_compose
        execute_docker_swarm
        execute_encrypt_ingress
        execute_configure_swarm_ports
        ;;
    * )
        usage
        terminate "No command specified"
esac

log "Done."

# TODO: add Docker/compose update
# TODO: add Docker/compose removal