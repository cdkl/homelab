# FoundryVTT VM Setup Guide

Complete documentation for setting up FoundryVTT as a standalone VM in Proxmox, integrated with existing homelab infrastructure including TinyAuth SSO and Let's Encrypt certificates.

## Overview

This guide covers the complete transition from a Kubernetes-based FoundryVTT deployment to a standalone VM setup with:
- **VM Infrastructure**: Terraform-managed Proxmox VM with cloud-init
- **FoundryVTT Service**: Node.js-based systemd service
- **SSL/TLS**: Let's Encrypt certificates via Cloudflare DNS-01
- **Authentication**: TinyAuth SSO integration via nginx
- **External Access**: Cloudflare Tunnel integration

## Prerequisites

- Proxmox VE with `ubuntu-24-04-template`
- Existing homelab infrastructure (K3s cluster, TinyAuth, DNS)
- Cloudflare API token with DNS edit permissions
- FoundryVTT license and download access

## Part 1: VM Infrastructure Setup

### 1.1 Terraform Configuration

**File**: `01-cluster/foundryvtt.tf`

```hcl
# FoundryVTT VM - Standalone virtual tabletop server
# This VM runs outside the K3s cluster for better performance and simpler management

resource "proxmox_vm_qemu" "foundryvtt" {
    name        = "foundryvtt"
    agent       = 1
    target_node = var.proxmox_node
    clone       = "ubuntu-24-04-template"

    os_type  = "cloud-init"
    cores    = 2
    memory   = 4096
    sockets  = 1
    onboot   = true
    startup  = "order=3"  # Start after K3s cluster

    # Cloud-Init configuration - using dedicated FoundryVTT cloud-init file
    cicustom   = "vendor=local:snippets/foundryvtt-user-data.yml"
    ciupgrade  = true

    scsihw = "virtio-scsi-single"

    disks {
        ide {
            ide2 {
                cloudinit {
                    storage = "local-lvm"
                }
            }
        } 
    
        scsi {
            scsi0 {
                disk {
                    size = "32G"  # OS + FoundryVTT data
                    storage = "local-lvm"
                }
            }
        }
    }

    network {
        id     = 0
        model  = "virtio"
        bridge = "vmbr0"
        macaddr = "52:54:00:00:00:10"  # Unique MAC for consistent IP
    }

    ipconfig0 = "ip=dhcp"
    sshkeys = file(pathexpand(var.ssh_public_key_path))
}

# Output FoundryVTT VM IP for use in Stage 2 DNS configuration
output "foundryvtt_ip" {
  value = proxmox_vm_qemu.foundryvtt.default_ipv4_address
  description = "IP address of the FoundryVTT VM"
}

# Output SSH connection command for easy access
output "foundryvtt_ssh_command" {
  value = "ssh ${var.proxmox_vm_user}@${proxmox_vm_qemu.foundryvtt.default_ipv4_address}"
  description = "SSH command to connect to FoundryVTT VM"
}
```

### 1.2 Cloud-Init Configuration

**File**: `01-cluster/cloud-init/foundryvtt-user-data.yml`

```yaml
#cloud-config
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - wget
  - unzip
  - nginx
  - certbot
  - python3-certbot-nginx

runcmd:
  # Enable and start qemu-guest-agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  
  # Set non-interactive mode for package installation
  - export DEBIAN_FRONTEND=noninteractive
  - export NEEDRESTART_MODE=a
  
  # Install Node.js 20.x (required for FoundryVTT) with error handling
  - curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || echo "NodeSource setup failed, continuing..."
  - apt-get update
  - apt-get install -y nodejs || (echo "NodeSource nodejs failed, trying Ubuntu nodejs" && apt-get install -y nodejs npm)
  
  # Create FoundryVTT user and directories
  - useradd -m -s /bin/bash foundryvtt
  - mkdir -p /opt/foundryvtt/app
  - mkdir -p /opt/foundryvtt/data
  - chown -R foundryvtt:foundryvtt /opt/foundryvtt
  
  # Install PM2 for process management (if npm is available)
  - which npm && npm install -g pm2 || echo "NPM not available, skipping PM2"
  
  # Create systemd service for FoundryVTT
  - systemctl daemon-reload

# Set password authentication to false for security
ssh_pwauth: false

# Default user configuration (matches existing pattern)
user: bunker
groups: [sudo]
shell: /bin/bash
sudo: ALL=(ALL) NOPASSWD:ALL

write_files:
  - path: /etc/systemd/system/foundryvtt.service
    content: |
      [Unit]
      Description=FoundryVTT Server
      After=network.target
      
      [Service]
      Type=simple
      User=foundryvtt
      Group=foundryvtt
      WorkingDirectory=/opt/foundryvtt/app
      ExecStart=/usr/bin/node /opt/foundryvtt/app/main.js --dataPath=/opt/foundryvtt/data --port=30000
      Restart=always
      RestartSec=10
      Environment=NODE_ENV=production
      
      [Install]
      WantedBy=multi-user.target
    owner: root:root
    permissions: '0644'
    
  - path: /etc/nginx/sites-available/foundryvtt
    content: |
      server {
          listen 80;
          server_name foundryvtt.cdklein.com;
          return 301 https://$server_name$request_uri;
      }

      server {
          listen 443 ssl http2;
          server_name foundryvtt.cdklein.com;

          # SSL configuration will be handled by certbot
          # ssl_certificate and ssl_certificate_key will be added by certbot

          location / {
              proxy_pass http://localhost:30000;
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              
              # WebSocket support for FoundryVTT
              proxy_http_version 1.1;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";
              
              # Increase proxy timeout for large file uploads
              proxy_read_timeout 300s;
              proxy_connect_timeout 75s;
          }
      }
    owner: root:root
    permissions: '0644'
```

### 1.3 VM Deployment

```bash
# Upload cloud-init file to Proxmox
scp ./cloud-init/foundryvtt-user-data.yml root@bunker1.cdklein.com:/var/lib/vz/snippets/

# Deploy VM
cd 01-cluster
terraform init
terraform plan -target=proxmox_vm_qemu.foundryvtt
terraform apply -target=proxmox_vm_qemu.foundryvtt

# Verify deployment
terraform output foundryvtt_ip
# Expected output: "192.168.101.204"
```

## Part 2: FoundryVTT Installation

### 2.1 Install FoundryVTT

```bash
# Connect to VM
ssh bunker@192.168.101.204

# Switch to foundryvtt user and install
sudo -u foundryvtt bash -c "
  cd /opt/foundryvtt/app
  # Download FoundryVTT using your license URL
  wget 'YOUR_FOUNDRY_DOWNLOAD_URL_HERE' -O foundry.zip
  unzip foundry.zip
  rm foundry.zip
  ls -la
"

# Verify Node.js version (must be 20+)
node --version
# Expected: v20.19.5 or higher
```

### 2.2 Configure FoundryVTT Service

```bash
# Enable and start the FoundryVTT service
sudo systemctl enable foundryvtt.service
sudo systemctl start foundryvtt.service

# Check status
sudo systemctl status foundryvtt.service

# View logs
sudo journalctl -u foundryvtt -f
```

### 2.3 Service Management Commands

```bash
# Basic service control
sudo systemctl start foundryvtt     # Start FoundryVTT
sudo systemctl stop foundryvtt      # Stop FoundryVTT  
sudo systemctl restart foundryvtt   # Restart FoundryVTT
sudo systemctl status foundryvtt    # Check status

# Logging
sudo journalctl -u foundryvtt -f    # Follow live logs
sudo journalctl -u foundryvtt -n 50 # View recent logs

# Check if port is listening
ss -tlnp | grep :30000
```

### 2.4 Data Migration (Historical)

For reference, data was migrated from the Kubernetes deployment:

```bash
# Extract data from Kubernetes pod
kubectl cp foundryvtt-0:/data/Backups ./foundryvtt-backups

# Transfer to VM
scp -r ./foundryvtt-backups bunker@192.168.101.204:/tmp/

# Extract and set permissions on VM
ssh bunker@192.168.101.204 '
sudo tar -xzf /tmp/foundryvtt-backup.tar.gz -C /opt/foundryvtt/data/
sudo chown -R foundryvtt:foundryvtt /opt/foundryvtt/data/
'
```

## Part 3: DNS Configuration

### 3.1 Update DNS Record

Update the DNS record in `02-services/foundryvtt.tf`:

```hcl
# DNS record for FoundryVTT - points to VM directly (transitioned from K3s to VM)
resource "technitium_dns_zone_record" "foundryvtt_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "foundryvtt.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = data.terraform_remote_state.cluster.outputs.foundryvtt_ip  # VM IP from Stage 1
}
```

### 3.2 Apply DNS Changes

```bash
cd 02-services
terraform apply -target=technitium_dns_zone_record.foundryvtt_cdklein

# Verify DNS resolution
nslookup foundryvtt.cdklein.com
# Expected: 192.168.101.204
```

## Part 4: Nginx and SSL Configuration

### 4.1 Basic Nginx Setup

```bash
# Enable basic HTTP configuration for testing
ssh bunker@192.168.101.204 '
sudo ln -sf /etc/nginx/sites-available/foundryvtt /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Test HTTP access
curl -I http://foundryvtt.cdklein.com
# Expected: 301 redirect to HTTPS
'
```

### 4.2 Let's Encrypt Certificate Setup

```bash
# Install Cloudflare DNS plugin
sudo apt update
sudo apt install -y python3-certbot-dns-cloudflare

# Create Cloudflare credentials file
sudo mkdir -p /etc/letsencrypt
sudo tee /etc/letsencrypt/cloudflare.ini > /dev/null << EOF
# Cloudflare API token used by Certbot
dns_cloudflare_api_token = YOUR_CLOUDFLARE_API_TOKEN_HERE
EOF
sudo chmod 600 /etc/letsencrypt/cloudflare.ini

# Get Let's Encrypt certificate
sudo certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60 \
  -d foundryvtt.cdklein.com \
  --non-interactive \
  --agree-tos \
  --email admin@cdklein.com

# Verify certificate creation
sudo ls -la /etc/letsencrypt/live/foundryvtt.cdklein.com/
```

### 4.3 TinyAuth Integration

Create the final nginx configuration with TinyAuth SSO:

```bash
sudo tee /etc/nginx/sites-available/foundryvtt-letsencrypt > /dev/null << 'EOF'
server {
    listen 80;
    server_name foundryvtt.cdklein.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name foundryvtt.cdklein.com;

    # Let's Encrypt certificate
    ssl_certificate /etc/letsencrypt/live/foundryvtt.cdklein.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/foundryvtt.cdklein.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # TinyAuth subrequest for nginx
    location = /auth {
        internal;
        proxy_pass https://auth.cdklein.com/api/auth/nginx;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header X-Original-URI $request_uri;
        proxy_set_header X-Original-Method $request_method;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location / {
        # Check authentication
        auth_request /auth;
        
        # Pass authentication headers from TinyAuth
        auth_request_set $user $upstream_http_x_forwarded_user;
        proxy_set_header X-Forwarded-User $user;
        
        # If auth fails, redirect to TinyAuth login
        error_page 401 = @auth_redirect;
        error_page 403 = @auth_redirect;
        
        # Proxy to FoundryVTT
        proxy_pass http://localhost:30000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
    
    # Handle authentication failures by redirecting to TinyAuth
    location @auth_redirect {
        return 302 https://auth.cdklein.com/?redirect_url=https://$host$request_uri;
    }
}
EOF

# Activate the configuration
sudo ln -sf /etc/nginx/sites-available/foundryvtt-letsencrypt /etc/nginx/sites-enabled/foundryvtt
sudo nginx -t
sudo systemctl reload nginx
```

### 4.4 Certificate Management

```bash
# Test automatic renewal
sudo certbot renew --dry-run

# Check certificate status
sudo certbot certificates

# Manual renewal (if needed)
sudo certbot renew

# Certificate auto-renewal is configured via systemd timer
systemctl list-timers | grep certbot
```

## Part 5: Integration with Existing Infrastructure

### 5.1 VM Network Configuration

- **IP Address**: 192.168.101.204 (DHCP reservation via MAC address)
- **MAC Address**: 52:54:00:00:00:10 (consistent IP assignment)
- **Network**: vmbr0 bridge (same as K3s cluster)

### 5.2 Cloudflare Tunnel Integration

The VM integrates with existing Cloudflare Tunnel for external access. The tunnel configuration needs to be updated to point to the VM instead of the Kubernetes service.

### 5.3 Relationship to K3s Cluster

- **DNS**: Managed by Technitium DNS on K3s cluster
- **Authentication**: TinyAuth service running on K3s cluster
- **External Access**: Cloudflare Tunnel running on K3s cluster
- **Independence**: FoundryVTT can run independently of K3s cluster

## Part 6: Security Considerations

### 6.1 SSL/TLS Configuration

- **Let's Encrypt Certificate**: Trusted CA certificate, automatic renewal
- **TLS Versions**: TLS 1.2 and 1.3 only
- **Cipher Suites**: High security ciphers only
- **HTTPS Redirect**: All HTTP traffic redirected to HTTPS

### 6.2 Authentication Integration

- **SSO**: Single Sign-On via TinyAuth
- **API Endpoint**: Uses `/api/auth/nginx` (nginx-specific endpoint)
- **Session Management**: Handled by TinyAuth service
- **Access Control**: All requests require authentication

### 6.3 Firewall Configuration

The VM relies on network-level security:
- **Internal Access**: All traffic on local network
- **External Access**: Only via authenticated Cloudflare Tunnel
- **No Direct Exposure**: No ports directly exposed to internet

## Part 7: Monitoring and Troubleshooting

### 7.1 Log Locations

```bash
# FoundryVTT Application Logs
sudo journalctl -u foundryvtt -f

# Nginx Access/Error Logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Certbot Logs
sudo tail -f /var/log/letsencrypt/letsencrypt.log

# System Logs
sudo journalctl -f
```

### 7.2 Health Checks

```bash
# Check FoundryVTT service status
sudo systemctl status foundryvtt

# Check if FoundryVTT is listening
ss -tlnp | grep :30000

# Test HTTP/HTTPS access
curl -I http://foundryvtt.cdklein.com   # Should redirect to HTTPS
curl -I -k https://foundryvtt.cdklein.com  # Should redirect to auth

# Verify certificate
openssl s_client -connect foundryvtt.cdklein.com:443 -servername foundryvtt.cdklein.com
```

### 7.3 Common Issues and Solutions

#### Issue: FoundryVTT won't start
```bash
# Check Node.js version (must be 20+)
node --version

# Check file permissions
sudo chown -R foundryvtt:foundryvtt /opt/foundryvtt

# Check systemd service
sudo systemctl status foundryvtt
```

#### Issue: SSL certificate errors
```bash
# Check certificate validity
sudo certbot certificates

# Test renewal
sudo certbot renew --dry-run

# Check nginx configuration
sudo nginx -t
```

#### Issue: Authentication not working
```bash
# Test TinyAuth endpoint
curl -k https://auth.cdklein.com/api/auth/nginx

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log

# Verify TinyAuth service is running
kubectl get pods -l app=tinyauth
```

## Part 8: VM Management

### 8.1 Resource Specifications

- **CPU**: 2 cores
- **Memory**: 4GB RAM
- **Storage**: 32GB (OS + FoundryVTT data)
- **Network**: virtio bridge to vmbr0

### 8.2 Backup Strategies

```bash
# FoundryVTT data backup
sudo tar -czf /backup/foundryvtt-data-$(date +%Y%m%d).tar.gz /opt/foundryvtt/data/

# VM snapshot (via Proxmox)
# Create snapshot in Proxmox web interface or CLI

# Configuration backup
sudo tar -czf /backup/foundryvtt-config-$(date +%Y%m%d).tar.gz \
  /etc/nginx/sites-available/foundryvtt-letsencrypt \
  /etc/systemd/system/foundryvtt.service \
  /etc/letsencrypt/
```

### 8.3 Maintenance Tasks

```bash
# Regular system updates
sudo apt update && sudo apt upgrade

# FoundryVTT updates
# Stop service, replace files, start service
sudo systemctl stop foundryvtt
sudo -u foundryvtt bash -c "cd /opt/foundryvtt/app && wget NEW_FOUNDRY_URL -O foundry.zip && unzip foundry.zip"
sudo systemctl start foundryvtt

# Certificate renewal (automatic via cron)
sudo certbot renew
```

## Conclusion

This setup provides a production-ready FoundryVTT deployment with:
- **High Availability**: Systemd service management with auto-restart
- **Security**: Let's Encrypt SSL + TinyAuth SSO integration
- **Performance**: Dedicated VM resources, no container overhead
- **Maintainability**: Standard system administration tools
- **Integration**: Seamless integration with existing homelab infrastructure

The transition from Kubernetes to VM provides better resource control and simpler administration while maintaining all security and authentication features.
