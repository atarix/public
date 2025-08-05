#!/bin/bash

set -e

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <user_name>"
  exit 1
fi

USER_NAME="$1"
# Variables
COMPOSE_FILE="/home/$USER_NAME/compose.yaml"  # <-- Set this to your compose file path

# Upgrade packages
sudo apt-get update
sudo apt-get upgrade -y

# Add Docker’s official GPG key and repository
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker and Docker Compose
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker "$USER"

# Enable IPv4 forwarding
echo "net.ipv4.conf.all.forwarding=1" | sudo tee /etc/sysctl.d/enabled_ipv4_forwarding.conf
sudo sysctl -p /etc/sysctl.d/enabled_ipv4_forwarding.conf

# Write systemd service for Docker Compose
sudo tee /etc/systemd/system/compose.service > /dev/null <<EOF
[Unit]
Description=Docker Compose
Requires=docker.service network-online.target
After=docker.service network-online.target

[Service]
ExecStart=docker compose -f ${COMPOSE_FILE} up
ExecStop=docker compose -f ${COMPOSE_FILE} stop
ExecStopPost=docker compose -f ${COMPOSE_FILE} down

Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable --now --no-block compose.service

echo "Deployment complete. You may need to log out and back in for docker group changes to take effect."


