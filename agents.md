# Homelab Infrastructure - Agent Context

## Overview
This repository contains a two-stage Terraform deployment for a Kubernetes-based homelab infrastructure running on Proxmox VE, with comprehensive DNS management and SSL certificate automation.

## Architecture Summary
- **Infrastructure Platform**: Proxmox VE virtualization
- **Orchestration**: K3s Kubernetes cluster (1 master, 2 workers)
- **Load Balancing**: MetalLB with static IP pool (192.168.101.233-243)
- **Storage**: Longhorn distributed block storage with NFS backup
- **DNS**: Technitium DNS Server with local domain management
- **SSL**: Cert-manager with Let's Encrypt + Cloudflare DNS-01 challenges
- **Ingress**: Traefik with automatic HTTPS redirects
- **Domain**: cdklein.com (local zone)

## Directory Structure
```
homelab/
├── agents.md            # This file - complete infrastructure overview
├── 01-cluster/          # Stage 1: Core infrastructure
│   ├── agents.md        # Stage 1 specific context and operations
│   ├── main.tf          # K3s cluster VMs (master + 2 workers)
│   ├── dns.tf           # Technitium DNS server deployment
│   ├── cert-manager.tf  # SSL certificate management
│   ├── metallb.tf       # Load balancer configuration
│   ├── longhorn.tf      # Distributed storage
│   └── cloud-init/      # VM initialization configs
└── 02-services/         # Stage 2: Applications and services
    ├── agents.md        # Stage 2 specific context and operations
    ├── birdnet-go.tf    # Bird identification service
    ├── kegserve.tf      # Personal keg management app
    ├── traefik-dashboard.tf # Ingress controller UI
    ├── dns-zone.tf      # DNS records for all services
    └── kubernetes/      # Static Kubernetes manifests
```

## Key Infrastructure Components

### VM Resources
- **Master Node**: 2 CPU, 4GB RAM, 20GB storage (192.168.101.x)
- **Worker Nodes**: 2 CPU, 3GB RAM, 20GB storage each (192.168.101.x)
- **Template**: ubuntu-24-04-template (cloud-init enabled)
- **Network**: vmbr0 bridge with DHCP assignment

### Network Configuration
- **Domain**: cdklein.com (managed by Technitium DNS)
- **MetalLB Pool**: 192.168.101.233-243
- **DNS Server**: 192.168.101.233 (Technitium LoadBalancer)
- **Traefik LoadBalancer**: 192.168.101.234

### Storage & Backup
- **Primary**: Longhorn distributed storage (default storage class)
- **Backup Target**: NFS to lorez.cdklein.com:/volume1/k3s/longhorn
- **Backup Schedule**: Daily at 6:03 AM, retain 7 days

## Deployed Applications

### Core Services
1. **Technitium DNS Server** (dns.cdklein.com)
   - Custom DNS zone management for cdklein.com
   - LoadBalancer service on 192.168.101.233
   - Admin interface on port 80

2. **Traefik Dashboard** (traefik.cdklein.com)
   - Ingress controller management interface
   - Automatic HTTPS with Let's Encrypt certificates

3. **Longhorn UI** (longhorn-ui.cdklein.com)
   - Storage management interface
   - Volume and backup monitoring

### Applications
1. **BirdNet-Go** (birdnet-go.cdklein.com)
   - Bird identification service
   - Uses NFS storage: /mnt/pve/nfs/birdnet-go-{config,data}

2. **KegServe** (kegserve.cdklein.com)
   - Personal keg management application
   - Rails app with Longhorn persistent storage
   - Uses Rails master key from Kubernetes secret

## Authentication & Security

### Single Sign-On (SSO) with TinyAuth
- **SSO Provider**: TinyAuth v3 (ghcr.io/steveiliop56/tinyauth:v3)
- **Domain**: auth.cdklein.com
- **Authentication Method**: ForwardAuth middleware integration with Traefik
- **Session Management**: HTTP-only secure cookies with 7-day expiry
- **User Storage**: Local users with bcrypt password hashing
- **Protected Services**: Traefik Dashboard, Longhorn UI

#### TinyAuth Configuration
- **Environment Variables**:
  - `APP_URL`: https://auth.cdklein.com
  - `COOKIE_SECURE`: true (HTTPS-only cookies)
  - `SESSION_EXPIRY`: 604800 (7 days)
  - `BACKGROUND_IMAGE`: https://static.cdklein.com/background.jpg
- **ForwardAuth Endpoint**: `/api/auth/traefik`
- **Authentication Flow**: 401 → Redirect to login → Session cookie → Access granted

#### Traefik ForwardAuth Integration
- **Middleware Configuration**: `tinyauth` middleware in each namespace
- **Auth Address**: `http://tinyauth.default.svc.cluster.local:3000/api/auth/traefik`
- **Response Headers**: `X-Forwarded-User`
- **Trust Forward Header**: true

#### Static Assets Server
- **Domain**: static.cdklein.com
- **Purpose**: Serves TinyAuth background images and static assets
- **Storage**: Longhorn PersistentVolume (1Gi)
- **Server**: Nginx Alpine with CORS headers
- **File Upload**: Use temporary pod with kubectl cp or kubectl exec

#### Protected Services Setup
1. **Traefik Dashboard**: 
   - IngressRoute with `tinyauth` middleware
   - Path matching: `/api` and `/dashboard`
   - Namespace: `kube-system`

2. **Longhorn UI**:
   - IngressRoute with `tinyauth` middleware  
   - Domain: longhorn.cdklein.com
   - Namespace: `longhorn-system`

### Certificates
- **Issuer**: Let's Encrypt via Cloudflare DNS-01 challenges
- **ClusterIssuer**: `letsencrypt-cloudflare`
- **Domains**: All services get automatic *.cdklein.com certificates
- **TinyAuth TLS**: Certificate for auth.cdklein.com
- **Static Assets TLS**: Certificate for static.cdklein.com

### SSH Access
- **User**: ubuntu (on all VMs)
- **Authentication**: SSH key-based (no passwords)
- **Key Paths**: ~/.ssh/id_rsa.pub (public), ~/.ssh/id_rsa (private)

### Secrets Management
- Cloudflare API token (for DNS challenges)
- Technitium admin password
- ACME email for Let's Encrypt
- Rails master key for KegServe
- TinyAuth secret key (randomly generated)
- TinyAuth user credentials (bcrypt hashed)

## Remote State Management
- **Backend**: PostgreSQL on lorez.local:15432
- **Database**: terraform_cluster
- **Connection**: Non-SSL for local network

## Common Operations

### Accessing Services
All services are available via HTTPS at their respective subdomains:
- https://traefik.cdklein.com (Traefik dashboard)
- https://dns.cdklein.com (Technitium DNS admin)
- https://longhorn-ui.cdklein.com (Storage management)
- https://birdnet-go.cdklein.com (Bird identification)
- https://kegserve.cdklein.com (Keg management)

### Kubernetes Access
```bash
# Get kubeconfig from master node
ssh ubuntu@<master-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
sed -i "s/127.0.0.1/<master-ip>/g" ~/.kube/config
```

### DNS Records
All service DNS records are automatically managed via the Technitium provider, pointing to appropriate LoadBalancer IPs or the master node IP.

## Important Notes
- Stage 01 must be fully deployed before Stage 02 (services depend on cluster state)
- Technitium DNS service must be running before Stage 02 can manage DNS records
- All services use automatic HTTPS with cert-manager and Let's Encrypt
- Storage uses Longhorn with daily NFS backups to Synology NAS (lorez)
- Local domain (.cdklein.com) provides internal service discovery and SSL
