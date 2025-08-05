#!/bin/bash

# Azure best practice: Use parameters for sensitive/configurable values
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <fqdn> <user_name> <admin_password>"
  exit 1
fi

FQDN="$1"
USER_NAME="$2"
ADMIN_PASSWORD="$3"

# 1. Mount the partitioned and formatted data disk
sudo mkdir -p /data
sudo mount /dev/sdc1 /data

# 2. Create Caddyfile
cat <<EOF > /home/$USER_NAME/Caddyfile
{
  #acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

${FQDN} {
  reverse_proxy seq:80
}
EOF

# 3. Create Docker Compose file
cat <<EOF > /home/$USER_NAME/compose.yaml
services:
  seq:
    image: datalust/seq:2024.3.13545
    environment:
      ACCEPT_EULA: Y
      SEQ_API_CANONICALURI: https://${FQDN}
      SEQ_FIRSTRUN_ADMINPASSWORD: ${ADMIN_PASSWORD}
    volumes:
      - /data/seq:/data

  caddy:
    image: caddy:2.8.4
    restart: unless-stopped
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - /data/caddy/data:/data
      - /data/caddy/config:/config
EOF

# 4. Set permissions
sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/Caddyfile /home/$USER_NAME/compose.yaml
sudo chmod 644 /home/$USER_NAME/compose.yaml

echo "Deployment files created. You can now run:"
echo "cd /home/$USER_NAME && docker compose -f compose.yaml up -d"

# 5. Download and run the data disk configuration script
# This script will partition, format, and mount the data disk
curl -O https://raw.githubusercontent.com/atarix/public/refs/heads/master/scripts/bash/data-disk-config.sh
chmod +x data-disk-config.sh
sudo ./data-disk-config.sh

# 6. Install Docker and Docker Compose
curl -O https://raw.githubusercontent.com/atarix/public/refs/heads/master/scripts/bash/docker-config.sh
chmod +x docker-config.sh
sudo ./docker-config.sh $USER_NAME

# 7. Start Docker Compose
sudo docker compose -f compose.yaml up -d