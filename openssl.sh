#!/bin/bash

# PASSPHRASE='thisisatest'
# HOST_NAME='notary-server' # TODO: temp
# HOST_IP='173.249.42.213' # TODO: temp
# CERT_DIR="/etc/docker/certs.d/$HOST_NAME"
# CLIENT_DIR="~/.docker"


execute_configure_docker_ssl() {
    # initialize and validate parameters
    local PASSPHRASE="$1"
    local HOST_NAME="$2"
    local HOST_IP="$3"
    local CERT_DIR="$4"
    local CLIENT_DIR="$5"
    [[( -z "$PASSPHRASE" || -z "$HOST_NAME" || -z "$HOST_IP" || -z "$CERT_DIR" || -z "$CLIENT_DIR" )]] && return 2

    # generate server certificates
    openssl genrsa -passout pass:"$PASSPHRASE" -aes256 -out ca-key.pem 4096 > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    openssl req -new -passin pass:"$PASSPHRASE" -x509 -days 1825 -key ca-key.pem -subj "/CN=$HOST_NAME" -sha256 \
        -out ca.pem > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    openssl genrsa -out server-key.pem 4096 > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    openssl req -subj "/CN=$HOST_NAME" -sha256 -new -key server-key.pem -out server.csr > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    echo "subjectAltName = DNS:$HOST_NAME,IP:$HOST_IP,IP:127.0.0.1" >> extfile.cnf
    echo extendedKeyUsage = serverAuth >> extfile.cnf
    openssl x509 -passin pass:"$PASSPHRASE" -req -days 1825 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
        -CAcreateserial -out server-cert.pem -extfile extfile.cnf > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1

    # generate client certificates
    openssl genrsa -out key.pem 4096 > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    openssl req -subj '/CN=client' -new -key key.pem -out client.csr > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1
    echo extendedKeyUsage = clientAuth > extfile-client.cnf
    openssl x509 -passin pass:"$PASSPHRASE" -req -days 1825 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
        -CAcreateserial -out cert.pem -extfile extfile-client.cnf > /dev/null 2>&1
    [ "$?" -ne 0 ] && return 1

    # clean-up files and set permissions
    rm -v client.csr server.csr extfile.cnf extfile-client.cnf > /dev/null 2>&1
    chmod -v 0400 ca-key.pem key.pem server-key.pem > /dev/null 2>&1
    chmod -v 0444 ca.pem server-cert.pem cert.pem > /dev/null 2>&1

    # copy server certificates
   mkdir -pv "$CERT_DIR"
   cp -v {ca,server-cert,server-key}.pem "$CERT_DIR"

    # copy client certificates
   mkdir -pv "$CLIENT_DIR"
   cp -v {ca,cert,key}.pem "$CLIENT_DIR"

    # update environment settings
    HOST_ARRAY=($(echo $HOST_NAME | tr " " "\n"))
    echo "DOCKER_HOST=tcp://${HOST_ARRAY[0]}:2376" | tee -a /etc/environment > /dev/null 2>&1
    echo "DOCKER_TLS_VERIFY=1" | tee -a /etc/environment > /dev/null 2>&1
}

#read -sp 'Pass phrase: ' PASSPHRASE
execute_configure_docker_ssl 'thisisatest' 'localhost notary-server' '173.249.42.213' '/etc/docker/certs.d/localhost' '~/.docker'
[ "$?" -ne 0 ] && echo "Error generating/installing certificates" && exit 1

systemctl daemon-reload
systemctl restart docker
systemctl enable docker
