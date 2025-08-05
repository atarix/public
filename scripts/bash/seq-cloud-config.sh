#!/bin/bash

# Azure best practice: Use parameters for sensitive/configurable values
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <fqdn> <admin_password>"
  exit 1
fi

FQDN="$1"
ADMIN_PASSWORD="$2"

# 1. Mount the partitioned and formatted data disk
sudo mkdir -p /data
sudo mount /dev/disk/azure/scsi1/lun0-part1 /data

# 2. Create Caddyfile
cat <<EOF > /home/azureuser/Caddyfile
{
  #acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

${FQDN} {
  reverse_proxy seq:80
}
EOF

# 3. Create Docker Compose file
cat <<EOF > /home/azureuser/compose.yaml
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
sudo chown azureuser:azureuser /home/azureuser/Caddyfile /home/azureuser/compose.yaml
sudo chmod 644 /home/azureuser/compose.yaml

echo "Deployment files created. You can now run:"
echo "cd /home/azureuser && docker compose -f compose.yaml up -d"