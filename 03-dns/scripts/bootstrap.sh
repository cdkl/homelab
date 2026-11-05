#!/usr/bin/env bash
set -euo pipefail

HOST="${1:?usage: bootstrap.sh <ip> <dns-domain> <admin-password>}"
DNS_DOMAIN="${2:?}"
ADMIN_PASSWORD="${3:?}"

ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "bunker@${HOST}" bash -s -- "$DNS_DOMAIN" "$ADMIN_PASSWORD" <<'REMOTE'
set -euo pipefail
DNS_DOMAIN="$1"
ADMIN_PASSWORD="$2"

sudo systemctl disable --now systemd-resolved || true
sudo rm -f /etc/resolv.conf
printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' | sudo tee /etc/resolv.conf >/dev/null

if ! command -v docker >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y docker.io ca-certificates curl
fi
sudo systemctl enable --now docker

sudo mkdir -p /opt/technitium/config /opt/technitium/logs
sudo docker rm -f dns-server 2>/dev/null || true
sudo docker pull technitium/dns-server:latest
sudo docker run -d \
  --name dns-server \
  --restart unless-stopped \
  --network host \
  -e "DNS_SERVER_DOMAIN=${DNS_DOMAIN}" \
  -e "DNS_SERVER_ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
  -e "DNS_SERVER_FORWARDERS=1.1.1.1, 9.9.9.9" \
  -e "DNS_SERVER_FORWARDER_PROTOCOL=Tls" \
  -e "DNS_SERVER_RECURSION=AllowOnlyForPrivateNetworks" \
  -v /opt/technitium/config:/etc/dns \
  -v /opt/technitium/logs:/var/log/technitium/dns \
  technitium/dns-server:latest
REMOTE
