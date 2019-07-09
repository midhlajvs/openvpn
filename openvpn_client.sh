#!/bin/bash

if readlink /proc/$$/exe | grep -q "dash"; then
        echo "This script needs to be run with bash, not sh"
        exit
fi

if [[ "$EUID" -ne 0 ]]; then
        echo "Sorry, you need to run this as root"
        exit
fi

if [[ ! -e /dev/net/tun ]]; then
        echo "The TUN device is not available
You need to enable TUN before running this script"
        exit
fi

function yellow { echo -e "\e[33m$@\e[0m" ; }
function red { echo -e "\e[31m$@\e[0m" ; }

SERVERNAME=server-name
SERVERCONF=$SERVERNAME/$SERVERNAME.conf
IP=1.2.3.4
PROTOCOL=tcp
PORT=1194


newclient () {
        # Generates the custom client.ovpn
        cp /etc/openvpn/$SERVERNAME/client-common.txt ~/$1.ovpn
        echo "<ca>" >> ~/$1.ovpn
        cat /etc/openvpn/$SERVERNAME/easy-rsa/pki/ca.crt >> ~/$1.ovpn
        echo "</ca>" >> ~/$1.ovpn
        echo "<cert>" >> ~/$1.ovpn
        sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/$SERVERNAME/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
        echo "</cert>" >> ~/$1.ovpn
        echo "<key>" >> ~/$1.ovpn
        cat /etc/openvpn/$SERVERNAME/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
        echo "</key>" >> ~/$1.ovpn
        echo "<tls-auth>" >> ~/$1.ovpn
        sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/$SERVERNAME/ta.key >> ~/$1.ovpn
        echo "</tls-auth>" >> ~/$1.ovpn
}



if [[ -e /etc/openvpn/$SERVERCONF ]]; then
        while :
        do
        clear
                yellow "Welcome to HostSailor WS Server user management script. "
                echo
                echo "What do you want to do?"
                echo "   1) Add a new user"
                echo "   2) Revoke an existing user"
                echo "   3) Exit"
                read -p "Select an option [1-3]: " option
                case $option in
                        1)
                        echo
                        echo "Tell me a name for the client certificate."
                        echo "Please, use one word only, no special characters."
                        read -p "Client name: " -e CLIENT
                        cd /etc/openvpn/$SERVERNAME/easy-rsa/
                        EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full $CLIENT nopass
                        # Generates the custom client.ovpn
                        newclient "$CLIENT"
                        echo
                        yellow "Client $CLIENT added, configuration is available at:" ~/"$CLIENT.ovpn"
                        exit
                        ;;
                        2)
                        # This option could be documented a bit better and maybe even be simplified
                        #
                        NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/$SERVERNAME/easy-rsa/pki/index.txt | grep -c "^V")
                        if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
                                echo
                                red "You have no existing clients!"
                                exit
                        fi
                        echo
                        echo "Select the existing client certificate you want to revoke:"
                        tail -n +2 /etc/openvpn/$SERVERNAME/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
                        if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
                                read -p "Select one client [1]: " CLIENTNUMBER
                        else
                                read -p "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
                        fi
                        CLIENT=$(tail -n +2 /etc/openvpn/$SERVERNAME/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
                        echo
                        read -p "Do you really want to revoke access for client $CLIENT? [y/N]: " -e REVOKE
                        if [[ "$REVOKE" = 'y' || "$REVOKE" = 'Y' ]]; then
                                cd /etc/openvpn/$SERVERNAME/easy-rsa/
                                ./easyrsa --batch revoke $CLIENT
                                EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
                                rm -f pki/reqs/$CLIENT.req
                                rm -f pki/private/$CLIENT.key
                                rm -f pki/issued/$CLIENT.crt
                                rm -f /etc/openvpn/$SERVERNAME/crl.pem
                                cp /etc/openvpn/$SERVERNAME/easy-rsa/pki/crl.pem /etc/openvpn/$SERVERNAME/crl.pem
                                # CRL is read with each client connection, when OpenVPN is dropped to nobody
                                chown nobody:$GROUPNAME /etc/openvpn/$SERVERNAME/crl.pem
                                echo
                                red "Certificate for client $CLIENT revoked!"
                        else
                                echo
                                echo "Certificate revocation for client $CLIENT aborted!"
                        fi
                        exit
                        ;;
                        3) exit;;
                        *) red "No clients selected to remove"
                           exit;;
                esac
        done
else
    echo "No OpenVPN Server configuration found ... Are you running the correct script? "
fi
exit


echo "client
dev tun
proto $PROTOCOL
sndbuf 0
rcvbuf 0
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
setenv opt block-outside-dns
key-direction 1
verb 3" > /etc/openvpn/$SERVERNAME/client-common.txt
        # Generates the custom client.ovpn
        newclient "$CLIENT"
        echo
        echo "Finished!"
        echo
        yellow "Your client configuration is available at:" ~/"$CLIENT.ovpn"
        echo "If you want to add more clients, you simply need to run this script again!"
fi
