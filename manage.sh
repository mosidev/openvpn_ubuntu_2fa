#!/bin/bash

ACTION=$1
CLIENT=$2
USER_EMAIL=$3
CLIENT_DIR="/opt/openvpn/clients"
GOOGLE_AUTH_DIR="/opt/openvpn/google-auth"
USER_DATA_DIR="/opt/openvpn/user-data"
ISSUER_NAME=
EXPIRE_DAYS=186
PW=

R="\e[0;91m"
G="\e[0;92m"
W="\e[0;97m"
B="\e[1m"
C="\e[0m"


function emailProfile() {
    local subject="Your OpenVPN profile"
    local content="""
OpenVPN connection profile for (${ISSUER_NAME})

use the attached VPN profile to connect using OpenVPN Connect.
    """

    echo "${content}" | mutt -s "${subject}" -a "${CLIENT_DIR}/${CLIENT}.zip" -- "${USER_EMAIL}" || { echo "${R}${B}error mailing profile to client: ${CLIENT}${C}"; exit 1; }
    echo "The user profile successfully sent to: ${USER_EMAIL}"
}

function newClient() {
    CLIENT=${1:?}
    CLIENT_EXISTS=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -c -E "/CN=${CLIENT}\$")
    if [[ $CLIENT_EXISTS == '1' ]]; then
        echo -e "${W}The specified client CN was already found in easy-rsa, please choose another name.${C}"
        exit
    else
        echo -e "${W}new user does not exist, creating..${C}"
        # generate user password
        mkdir -p "${CLIENT_DIR}/${CLIENT}"
        mkdir -p "${USER_DATA_DIR}/${CLIENT}"
        #echo "${CLIENT}" > "${USER_DATA_DIR}/${CLIENT}/pass.txt"
        PW=$(pwgen -scB 15 1) || { echo -e "${R}${B}Error generating password for ${CLIENT} ${C}"; exit 1; }
        echo "${PW}" >> "${USER_DATA_DIR}/${CLIENT}/pass.txt"

        cd /etc/openvpn/server/easy-rsa/ || return
        ./easyrsa --days=${EXPIRE_DAYS} build-client-full "${CLIENT}" nopass <<<yes
        echo -e "${G}Client $CLIENT added.${C}"
    fi

    # create system account for new VPN user, add password to it
    user_exists=$(grep -c "^${CLIENT}:" /etc/passwd)
    if [ $user_exists -eq 0 ]; then
        useradd -m -d "${CLIENT_DIR}/${CLIENT}" -s /usr/sbin/nologin "${CLIENT}" || { echo -e "${R}${B}Error creating system account for ${CLIENT} ${C}"; exit 1; }
    fi

    # update system user pw, remove pw expiration
    echo "${CLIENT}:${PW}" | chpasswd
    chage -m 0 -M 99999 -I -1 -E -1 "${CLIENT}"

    # generates the custom client.ovpn
    cp "${CLIENT_DIR}/client-template.txt" "${CLIENT_DIR}/${CLIENT}/${CLIENT}.ovpn"
    {
        echo "<ca>"
        cat "/etc/openvpn/server/easy-rsa/pki/ca.crt"
        echo "</ca>"
        echo "<cert>"
        awk '/BEGIN/,/END/' "/etc/openvpn/server/easy-rsa/pki/issued/${CLIENT}.crt"
        echo "</cert>"
        echo "<key>"
        cat "/etc/openvpn/server/easy-rsa/pki/private/${CLIENT}.key"
        echo "</key>"
        echo "<tls-crypt>"
        cat /etc/openvpn/server/tc.key
        echo "</tls-crypt>"
    } >>"${CLIENT_DIR}/${CLIENT}/${CLIENT}.ovpn"

    chown -R root:root "${CLIENT_DIR}/${CLIENT}"

    echo -e "${W}The configuration file has been written to ${CLIENT_DIR}/${CLIENT}/${CLIENT}.ovpn${C}"
}

function createUser() {
    [ -z "${ISSUER_NAME}" ] && { echo -e "${R}Update the ISSUER_NAME variable at the top of this file with a value, such as your company name.${C}"; exit 1; }
    [ -z "${CLIENT}" ] && { echo -e "${R}Provide a username to create${C}"; exit 1; }
    [ -z "${USER_EMAIL}" ] && { echo -e "${R}Provide an email to create${C}"; exit 1; }

    newClient "${CLIENT}" || { echo -e "${R}${B}Error generating user VPN profile${C}"; exit 1; }

    # setup Google Authenticator
    mkdir -p "${GOOGLE_AUTH_DIR}/${CLIENT}"
    mkdir -p "${USER_DATA_DIR}/${CLIENT}"
    google-authenticator -t -d -f -q -r 3 -R 600 -w 5 -C -s "${GOOGLE_AUTH_DIR}/${CLIENT}/${CLIENT}" || { echo -e "${R}${B}error generating QR code${C}"; exit 1; }
    secret=$(head -n 1 "${GOOGLE_AUTH_DIR}/${CLIENT}/${CLIENT}")
    qrencode -t PNG -o "${USER_DATA_DIR}/${CLIENT}/${CLIENT}.png" "otpauth://totp/${CLIENT}?secret=${secret}&issuer=${ISSUER_NAME}" || { echo -e "${R}${B}Error generating PNG${C}"; exit 1; }
    chmod 600 "${USER_DATA_DIR}/${CLIENT}/${CLIENT}.png"

    cd "${CLIENT_DIR}"
    zip -r -m -q -P "${PW}" "${CLIENT}.zip" "${CLIENT}"
    cd -
    emailProfile || { echo -e "${R}${B}Error sending profile to new user ${CLIENT} ${C}"; exit 1; }
}

function revokeUser() {
    [ -z "${CLIENT}" ] &&  { echo -e "${R}Provide a username to revoke${C}"; exit 1; }

    cd /etc/openvpn/server/easy-rsa/ || exit 1
    ./easyrsa --batch revoke "${CLIENT}"
    EASYRSA_CRL_DAYS=${EXPIRE_DAYS} ./easyrsa gen-crl
    rm -f "pki/reqs/${CLIENT}.req*"
    rm -f "pki/private/${CLIENT}.key*"
    rm -f "pki/issued/${CLIENT}.crt*"
    rm -f /etc/openvpn/crl.pem
    cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
    chmod 644 /etc/openvpn/crl.pem

    # remove client from PKI index
    sed -i "/CN=${CLIENT}$/d" /etc/openvpn/server/easy-rsa/pki/index.txt

    rm -f "${CLIENT_DIR:?}/${CLIENT:?}.zip"
    rm -rf "${GOOGLE_AUTH_DIR:?}/${CLIENT:?}"
    rm -rf "${USER_DATA_DIR:?}/${CLIENT:?}"

    # remove user OS acct that was created by OpenVPN manage.sh script
    id "${CLIENT}" && userdel -r -f "${CLIENT}" || { echo -e "${R}${B}Error revoking ${CLIENT} ${C}"; exit 1; }
    echo -e "${G}VPN access for $CLIENT is revoked${C}"
}

function refreshUser() {
    [ -z "${ISSUER_NAME}" ] && { echo -e "${R}Update the ISSUER_NAME variable at the top of this file with a value, such as your company name.${C}"; exit 1; }
    [ -z "${CLIENT}" ] && { echo -e "${R}Provide a username to refresh${C}"; exit 1; }
    [ -z "${USER_EMAIL}" ] && { echo -e "${R}Provide an email to refresh${C}"; exit 1; }

    revokeUser
    createUser
}

function statusUsers() {
    cat /etc/openvpn/server/easy-rsa/pki/index.txt | grep "^V" | grep -v "server_"
}


cd /opt/openvpn || exit 1

if [ "${ACTION}" == "create" ]; then
    createUser
elif [ "${ACTION}" == "revoke" ]; then
    revokeUser
elif [ "${ACTION}" == "refresh" ]; then
    refreshUser
elif [ "${ACTION}" == "status" ]; then
    statusUsers
else
    message="""
${W}usage:
  ./manage.sh create <username> <email>
  ./manage.sh revoke <username>
  ./manage.sh refresh <username> <email>
  ./manage.sh status${C}
    """
    echo -e "${message}"
    exit 1
fi
