#!/bin/bash
# Installs 2FA components for OpenVPN on ubuntu
# please install the openvpn community server with this repo: https://github.com/Nyr/openvpn-install
# Code taken from this repo: https://github.com/perfecto25/openvpn_2fa
# and adjusted specifically for ubuntu 24.04


apt install -y libpam-google-authenticator pwgen qrencode zip msmtp msmtp-mta mailutils
mkdir -p /opt/openvpn/clients
cp files/msmtprc.txt $HOME/.msmtprc
cp files/etc-pamd-openvpn /etc/pam.d/openvpn
cp files/client-template.txt /opt/openvpn/clients/

# Please compare files/etc-openvpn-server-server.conf with /etc/openvpn/server/server.conf and add desired lines manually!
