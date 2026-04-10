#!/bin/bash

set -e

# Check if all parameters are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <NATed_IP_ADDRESS> <SOURCE_IP_CIDR> <DESTINATION_IP_CIDR>"
    
    exit 1
fi

# Assign the parameters to variables
NATed_IP_ADDRESS=$1
SOURCE_IP_CIDR=(${2//,/ })
DESTINATION_IP_CIDR=(${3//,/ })

#Create the directory:
sudo mkdir -p /etc/iptables


#Configure iptables: Use iptables to set up the NAT rule to translate the source IP to the defined NATed IP address.

# Enable IP Forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Set up NAT for traffic from source to destination
for DEST in "${DESTINATION_IP_CIDR[@]}"; do
    for SOURCE in "${SOURCE_IP_CIDR[@]}"; do
        sudo iptables -t nat -A POSTROUTING -s $SOURCE -d $DEST -j SNAT --to-source $NATed_IP_ADDRESS
    done
done
    

# Add a rule to forward traffic to the destination
for DEST in "${DESTINATION_IP_CIDR[@]}"; do
    sudo iptables -A FORWARD -d $DEST -j ACCEPT
    sudo iptables -A FORWARD -s $DEST -j ACCEPT
done


#Persist iptables Rules:
sudo sh -c "iptables-save > /etc/iptables/rules.v4"

