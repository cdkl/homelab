# Homelab Services Infrastructure (Stage 2)

**Note**: This is part of a larger homelab infrastructure. See `../agents.md` for the complete overview.

## Current Directory: 02-services
This directory focuses on secondary service deployments (Stage 2). Ensure Stage 1 is fully applied, as these services depend on the core infrastructure.

## What's Here
This stage deploys individual applications with associated Kubernetes resources:

### Deployed Services
- **BirdNet-Go** (`birdnet-go.tf`): Bird identification service on Proxmox storage
- **KegServe** (`kegserve.tf`): Rails-based personal keg management
- **FoundryVTT** (`foundryvtt.tf`): Self-hosted virtual tabletop with TinyAuth SSO protection
- **Cloudflare Tunnel** (`cloudflare-tunnel.tf`): Secure external access with controllable on/off toggle
- **Traefik Dashboard** (`traefik-dashboard.tf`): Ingress management UI with TinyAuth SSO
- **TinyAuth** (`tinyauth.tf`): SSO authentication service for protected resources
- **TinyAuth Middleware** (`tinyauth-middleware.tf`): ForwardAuth middleware for Traefik
- **Static Assets** (`static-assets.tf`): Nginx server for TinyAuth background images
- **DNS Zone Configuration** (`dns-zone.tf`): Manages internal DNS records for services

### Required Variables
Ensure Stage 1 outputs are accessible; the services.tf files reference master node IPs, etc.

### Deployment Order
1. Ensure Stage 1 is fully deployed and Technitium DNS is active
2. Verify DNS and LoadBalancer IPs are available
3. Apply services with typical Terraform workflow:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Post-Deployment
After successful apply:
1. **Verify service access**:
```bash
kubectl get pods -n default
kubectl get svc -n default
```

2. **Local DNS management (Pi-hole v6)**
- Local overrides are applied via `pihole-FTL --config dns.hosts`/`dns.cnameRecords` by Terraform (see `pihole-local-dns.tf`).
- To add or change a hostname, edit the host map in `pihole-local-dns.tf` (or extend `local.merged_hosts`) and run:
```bash
terraform plan
terraform apply -target=null_resource.pihole_local_dns
```
- Validate:
```bash
nslookup pihole.cdklein.com 192.168.101.100
```

3. **Check services**:
- BirdNet-Go: http(s)://birdnet-go.cdklein.com
- KegServe: http(s)://kegserve.cdklein.com
- Traefik: http(s)://traefik.cdklein.com

### Key Resources Created
- **Pods/Deployments**: birdnet-go, kegserve
- **Kubernetes Services**: Exposing applications via LoadBalancer/IPs
- **Ingress Routes**: Configured to manage external access securely
- **DNS Records**: Technitium-managed for local domain

### Dependencies
Services require access to:
- K3s cluster nodes running and Alive
- MetalLB-assigned LoadBalancer IPs
- Let's Encrypt certificates for `*.cdklein.com`

### Troubleshooting
- **Pods not starting**: Check K8s events/logs for error messages
- **Ingress not working**: Verify Traefik is running and certificates are valid
- **DNS resolution fails**: Confirm Technitium DNS service is operational

## Single Sign-On (SSO) Authentication

### TinyAuth Overview
- **Service**: TinyAuth v3 container providing lightweight SSO
- **Domain**: auth.cdklein.com
- **Integration**: Traefik ForwardAuth middleware
- **Purpose**: Protect sensitive infrastructure services (Traefik Dashboard, Longhorn UI, FoundryVTT)

### Architecture Components

#### 1. TinyAuth Service (`tinyauth.tf`)
- **Container**: ghcr.io/steveiliop56/tinyauth:v3
- **Deployment**: Single replica in `default` namespace
- **Service**: ClusterIP on port 3000
- **Configuration**:
  ```env
  APP_URL=https://auth.cdklein.com
  COOKIE_SECURE=true
  SESSION_EXPIRY=604800  # 7 days
  BACKGROUND_IMAGE=https://static.cdklein.com/background.jpg
  USERS=user1:$bcrypt$hash,user2:$bcrypt$hash
  ```

#### 2. ForwardAuth Middleware
- **Location**: Multiple namespaces (`default`, `kube-system`, `longhorn-system`)
- **Configuration**:
  ```yaml
  spec:
    forwardAuth:
      address: http://tinyauth.default.svc.cluster.local:3000/api/auth/traefik
      authResponseHeaders: ["X-Forwarded-User"]
      trustForwardHeader: true
  ```

#### 3. Static Assets Server (`static-assets.tf`)
- **Purpose**: Serve custom background images for TinyAuth login page
- **Domain**: static.cdklein.com
- **Storage**: Longhorn PersistentVolume (1Gi)
- **Server**: Nginx Alpine with CORS headers
- **Upload Process**:
  ```bash
  # Create temporary upload pod
  kubectl apply -f upload-pod.yaml
  
  # Copy background image
  kubectl cp /path/to/background.jpg default/static-assets-uploader:/upload/background.jpg
  
  # Clean up
  kubectl delete pod static-assets-uploader
  ```

### Protected Services

#### Traefik Dashboard
- **IngressRoute**: Modified to include `tinyauth` middleware
- **Path Matching**: `Host(traefik.cdklein.com) && (PathPrefix(/api) || PathPrefix(/dashboard))`
- **Namespace**: `kube-system`
- **Middleware**: References `tinyauth` middleware in same namespace

#### Longhorn UI
- **IngressRoute**: Includes `tinyauth` middleware
- **Domain**: longhorn.cdklein.com
- **Namespace**: `longhorn-system`
- **Middleware**: Separate `tinyauth` middleware created in `longhorn-system`

### Authentication Flow
1. **User Access**: User visits protected service (e.g., traefik.cdklein.com/dashboard/)
2. **Middleware Check**: Traefik calls TinyAuth `/api/auth/traefik` endpoint
3. **Authentication Status**:
   - **Authenticated**: TinyAuth returns 200, request proceeds to service
   - **Unauthenticated**: TinyAuth returns 401, Traefik redirects to auth.cdklein.com
4. **Login Process**: User authenticates on TinyAuth login page
5. **Session Cookie**: TinyAuth sets secure session cookie
6. **Access Granted**: Subsequent requests pass through with valid session

### Troubleshooting SSO Issues

#### Common Problems
1. **401 Responses**: 
   - Check TinyAuth pod logs: `kubectl logs -n default deployment/tinyauth`
   - Verify middleware configuration: `kubectl get middleware -A`
   - Test auth endpoint: `kubectl exec -n default deployment/tinyauth -- curl -s http://localhost:3000/api/auth/traefik`

2. **Redirect Issues**:
   - Verify TinyAuth is accessible: `curl -I https://auth.cdklein.com`
   - Check certificate status: `kubectl get certificate -A`
   - Verify DNS resolution: `nslookup auth.cdklein.com`

3. **Middleware Not Found**:
   - Ensure middleware exists in correct namespace
   - Check IngressRoute references correct middleware name
   - Verify Traefik can access TinyAuth service

#### Debug Commands
```bash
# Check TinyAuth status
kubectl get pods -l app=tinyauth
kubectl logs -n default deployment/tinyauth --tail=20

# Check middleware configuration
kubectl get middleware -A
kubectl describe middleware tinyauth -n kube-system

# Test authentication endpoint
kubectl exec -n default deployment/tinyauth -- curl -v http://localhost:3000/api/auth/traefik

# Check certificates
kubectl get certificate -A
kubectl describe certificate tinyauth-letsencrypt-cert -n default
```

### Security Considerations
- **Session Cookies**: HTTP-only, secure, 7-day expiry
- **Password Storage**: bcrypt hashing for user credentials
- **HTTPS Only**: All authentication traffic over TLS
- **Domain Scoping**: Cookies scoped to .cdklein.com domain
- **ForwardAuth Headers**: X-Forwarded-User passed to backend services

### Important Notes
- Adjust resources allocated to services in manifests if necessary
- Certificates managed automatically via cert-manager
- Storage via Longhorn, with regular NFS backups
- TinyAuth requires proper user configuration via Terraform variables
- Static assets server allows customization of TinyAuth appearance

## FoundryVTT Virtual Tabletop

### Overview
- **Service**: Self-hosted FoundryVTT virtual tabletop for D&D and other RPGs
- **Domain**: foundryvtt.cdklein.com
- **Container**: felddy/foundryvtt:release
- **Deployment Type**: StatefulSet (for persistence and single-instance requirement)
- **Port**: 30000 (internal), 443 (external via HTTPS)

### Architecture Components

#### 1. StatefulSet Deployment (`foundryvtt.tf`)
- **Replicas**: 1 (FoundryVTT requires single instance)
- **Container**: felddy/foundryvtt:release
- **Resources**: 1Gi-2Gi RAM, 500m-2 CPU
- **Security Context**: Runs as user 1000:1000 for proper file permissions
- **Health Checks**: HTTP probes on port 30000 with extended timeouts

#### 2. Persistent Storage
- **Primary Data Volume**: 2Gi Longhorn PVC (`foundryvtt-data-pvc`)
  - Mount Point: `/data`
  - Contains: Worlds, modules, assets, configurations
- **Application Cache Volume**: 1Gi Longhorn PVC (`foundryvtt-app-pvc`)
  - Mount Points: `/home/node/.cache`, `/home/node/.local`, `/tmp`
  - Contains: Application state, temporary files, session data

#### 3. Configuration Management
- **Environment Variables**:
  ```env
  FOUNDRY_USERNAME=<license_username>
  FOUNDRY_PASSWORD=<license_password>
  FOUNDRY_RELEASE_URL=<timed_download_url>
  FOUNDRY_ADMIN_KEY=<admin_access_key>
  FOUNDRY_PROXY_SSL=true
  FOUNDRY_PROXY_PORT=443
  CONTAINER_PRESERVE_CONFIG=true
  ```
- **Persistent Config Files**:
  - `/data/Config/options.json`: Server settings
  - `/data/Config/admin.txt`: Admin access key (hashed)
  - `/data/Config/license.json`: Software license information

#### 4. Network Configuration
- **Service**: ClusterIP on port 30000
- **IngressRoute**: Traefik with automatic HTTPS
- **Certificate**: Let's Encrypt for foundryvtt.cdklein.com
- **DNS Record**: A record pointing to k3s master IP

### Required Terraform Variables
```hcl
# In terraform.tfvars
foundryvtt_username = "your-foundry-username"
foundryvtt_password = "your-foundry-password"
foundryvtt_release_url = "https://r2.foundryvtt.com/releases/..." # From FoundryVTT account
foundryvtt_admin_key = "your-admin-access-key"
```

### Deployment Process
1. **Prerequisites**:
   - Valid FoundryVTT license
   - Fresh download URL from FoundryVTT account (URLs expire!)
   - Sufficient storage space (6Gi total across 3 Longhorn replicas)

2. **Configuration**:
   - Set Terraform variables in `terraform.tfvars`
   - Apply with `terraform apply`

3. **First Startup**:
   - Container downloads FoundryVTT from release URL
   - Creates admin access key in `/data/Config/admin.txt`
   - Generates initial configuration files

### Persistence Strategy

#### Why StatefulSet vs Deployment?
- **Single Instance Requirement**: FoundryVTT cannot run multiple instances
- **Persistent Identity**: StatefulSet provides stable pod naming (`foundryvtt-0`)
- **Ordered Deployment**: Ensures single pod recreation on restart
- **Configuration Persistence**: Prevents configuration loss between restarts

#### Key Persistence Features
1. **Configuration Preservation**: `CONTAINER_PRESERVE_CONFIG=true` prevents overwriting
2. **Admin Key Persistence**: Admin access key survives pod restarts
3. **World Data**: All worlds, modules, and assets persist across restarts
4. **Server Settings**: User-configured server settings maintained

### Management Operations

#### Server Restart
```bash
# Clean restart - preserves all data and configuration
kubectl delete pod foundryvtt-0

# StatefulSet automatically recreates the pod
kubectl get pods -l app=foundryvtt
```

#### Configuration Access
- **Web Interface**: https://foundryvtt.cdklein.com
- **Admin Access**: Use the configured `foundryvtt_admin_key`
- **First Setup**: If no admin key, container warns in logs

#### Storage Management
```bash
# Check storage usage
kubectl exec foundryvtt-0 -- df -h /data

# View persistent volumes
kubectl get pvc | grep foundryvtt

# Check Longhorn volume status
kubectl get volumes.longhorn.io -n longhorn-system
```

### Troubleshooting

#### Common Issues
1. **Pod Stuck in ContainerCreating**:
   - Check storage availability: Longhorn needs 3x volume size across nodes
   - Verify PVC binding: `kubectl get pvc foundryvtt-data-pvc`
   - Check Longhorn volume status in UI

2. **Download Failures (403 Errors)**:
   - FoundryVTT download URLs expire after ~1 hour
   - Get fresh URL from FoundryVTT account
   - Update `foundryvtt_release_url` variable and reapply

3. **Configuration Not Persisting**:
   - Verify `CONTAINER_PRESERVE_CONFIG=true` is set
   - Check admin.txt file exists: `kubectl exec foundryvtt-0 -- ls -la /data/Config/`
   - Ensure proper file permissions (user 1000:1000)

4. **License Issues**:
   - Verify license credentials in Terraform variables
   - Check container logs for authentication errors
   - Ensure FoundryVTT account has available license slots

#### Debug Commands
```bash
# Check pod status and logs
kubectl get pods -l app=foundryvtt
kubectl logs foundryvtt-0 --tail=50

# Check persistent volumes
kubectl get pvc | grep foundryvtt
kubectl describe pvc foundryvtt-data-pvc

# Shell into container for file inspection
kubectl exec -it foundryvtt-0 -- /bin/bash

# Check configuration files
kubectl exec foundryvtt-0 -- ls -la /data/Config/
kubectl exec foundryvtt-0 -- cat /data/Config/options.json

# Monitor Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system
```

### Storage Considerations
- **Volume Size**: 2Gi data + 1Gi cache = 3Gi per pod
- **Replication**: Longhorn creates 3 replicas = 9Gi total storage needed
- **Available Space**: Ensure sufficient space across worker nodes
- **Backup**: Longhorn automatically backs up to NFS (lorez.cdklein.com)

### Security Notes
- **Admin Key**: Stored securely in Terraform variables (sensitive = true)
- **HTTPS Only**: All traffic encrypted via Traefik and Let's Encrypt
- **Internal Network**: Service only accessible via cluster network
- **License Credentials**: Stored in Kubernetes secrets

### Performance Tuning
- **Resource Limits**: Adjust CPU/memory limits based on player count
- **Storage Class**: Uses Longhorn for distributed storage and backup
- **Network**: Optimized for SSL termination at Traefik level
