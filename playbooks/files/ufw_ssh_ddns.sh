#!/bin/bash

#=======================================================================================================================
# Title         : ufw_ssh_ddns.sh
# Description   : Configures ufw to Enable SSH Access for the IP Address Associated With a DDNS Address
# Author        : Mark Dumay
# Date          : January 19th, 2021
# Version       : 0.9
# Usage         : sudo ./ufw_ssh_ddns.sh
# Repository    : https://github.com/markdumay/ubuntu-docker.git
#=======================================================================================================================

#=======================================================================================================================
# Constants
#=======================================================================================================================
readonly RED='\e[31m' # Red color
readonly NC='\e[m' # No color / reset
readonly BOLD='\e[1m' #Bold font
readonly LOG_PREFIX="$(date -u '+%F %T') "


#=======================================================================================================================
# Global Variables
#=======================================================================================================================
port=22
ddns_address=''
log_file='/var/log/ufw_ssh_ddns.log'


#=======================================================================================================================
# Helper Functions
#=======================================================================================================================

#=======================================================================================================================
# Displays error message on console and log file, terminate with non-zero error.
#=======================================================================================================================
# Arguments:
#   $1 - Error message to display.
# Outputs:
#   Writes error message to stderr and optional log file, non-zero exit code.
#=======================================================================================================================
terminate() {
    printf "${RED}${BOLD}%s${NC}\n" "ERROR: $1"
    if [ -n "${log_file}" ] ; then
        echo "${LOG_PREFIX}ERROR: $1" >> "${log_file}"
    fi
    exit 1
}

#=======================================================================================================================
# Prints current progress to the console and optional log file.
#=======================================================================================================================
# Arguments:
#   $1 - Progress message to display.
# Outputs:
#   Writes message to stdout and optional log file.
#=======================================================================================================================
log() {
    echo "$1"
    if [ -n "${log_file}" ] ; then
        echo "${LOG_PREFIX}$1" >> "${log_file}"
    fi
}


#=======================================================================================================================
# Helper Functions
#=======================================================================================================================

#=======================================================================================================================
# Retrieves the public IP address associated with a DDNS address and the currently configured IP address in ufw
# (identified by the comment). It updates the ufw configuration if the two address are different.
#=======================================================================================================================
# Globals:
#   - ddns_address
# Outputs:
#   Writes message to stdout and optional log file.
#=======================================================================================================================
update_ufw_rules() {
    log "INFO:  Configuring ufw for DDNS '${ddns_address}' at port '${port}'"

    # Identify old and new IP address
    newIP=$(dig "${ddns_address}" +short | tail -n 1)
    oldIP=$(/usr/sbin/ufw status | grep "${ddns_address}" | head -n1 | tr -s ' ' | cut -f3 -d ' ')

    # Update ufw configuration if needed
    if [ "${newIP}" == "${oldIP}" ] ; then
        log 'INFO:  IP address has not changed'
    else
        if [ -n "${oldIP}" ] ; then
            /usr/sbin/ufw delete allow from "${oldIP}" to any port "${port}"
        fi
        /usr/sbin/ufw allow from "${newIP}" to any port "${port}" comment "${ddns_address}"
        log 'INFO:  Updated ufw configuration'
    fi
}

#=======================================================================================================================
# Validates if a specified fully qualified domain name or subdomain adheres to the expected format. The protocol prefix
# http or https is stripped if applicable. The domain name is converted to lower case. International names need to be
# converted to punycode ('xn--*') first.
#=======================================================================================================================
# Globals:
#   - ddns_address
# Returns:
#   Terminates with a non-zero exit code if the domain is invalid.
#=======================================================================================================================
validate_ddns_address() {
    ddns_address=$(echo "${ddns_address}" | tr '[:upper:]' '[:lower:]')
    ddns_address="${ddns_address##http://}"
    ddns_address="${ddns_address##https://}"

    domain_regex='^((?=[a-z0-9-]{1,63}\.)(xn--)?[a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,63}$'
    match=$(echo "${ddns_address}" | grep -Pi "${domain_regex}")
    [ -z "${match}" ] && usage && terminate "Invalid or missing DDNS address"
}

#=======================================================================================================================
# Validates if a specified port is an integer between 1 and 65535.
#=======================================================================================================================
# Globals:
#   - port
# Returns:
#   Terminates with a non-zero exit code if the port is invalid.
#=======================================================================================================================
validate_port() {
    [ "${port}" -gt 0 ] && [ "${port}" -lt 65536 ] && return
    usage && terminate "Port needs to be between 1 and 65535"
}

#=======================================================================================================================
# Display usage message.
#=======================================================================================================================
# Globals:
#   - backup_dir
# Outputs:
#   Writes message to stdout.
#=======================================================================================================================
usage() {
    echo "Usage: $0 --ddns <ADDRESS> [--port <PORT>]"
    echo
    echo "Configures ufw to enables SSH access for a public IP address associated with a"
    echo "DDNS address. Messages are displayed on the console and written to the log file"
    echo "'${log_file}'."
    echo
    echo "Options:"
    echo "  --ddns ADDRESS        DDNS address to look up"
    echo "  --port PORT           SSH port, defaults to 22"
    echo
 }

#=======================================================================================================================
# Main Script
#=======================================================================================================================

#=======================================================================================================================
# Entrypoint for the script. It initializes the arguments and updates ufw with the newly found IP address if
# applicable.
#=======================================================================================================================
main() {
    # Test if script has root privileges, exit otherwise
    id=$(id -u)
    if [ "${id}" -ne 0 ]; then
        usage
        log_file='' # skip writing to log file as only sudoers have write access
        terminate "You need to be root to run this script"
    fi

    # Validate ufw is present and active, exit otherwise
    if ! (/usr/sbin/ufw status 2>/dev/null | grep -q 'Status: active'); then
        terminate "ufw is not active"
    fi

    # Process and validate command-line arguments
    while [ "$1" != "" ]; do
        case "$1" in
            --ddns )
                shift
                ddns_address="$1"
                ;;
            --port )
                shift
                port="$1"
                validate_port
                ;;
            * )
                usage
                terminate "Unrecognized parameter ($1)"
        esac
        shift
    done

    # Validate mandatory options
    validate_ddns_address

    # Execute command
    update_ufw_rules
}

main "$@"