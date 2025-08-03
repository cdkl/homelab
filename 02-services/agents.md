# Homelab Services Infrastructure (Stage 2)

**Note**: This is part of a larger homelab infrastructure. See `../agents.md` for the complete overview.

## Current Directory: 02-services
This directory focuses on secondary service deployments (Stage 2). Ensure Stage 1 is fully applied, as these services depend on the core infrastructure.

## What's Here
This stage deploys individual applications with associated Kubernetes resources:

### Deployed Services
- **BirdNet-Go** (`birdnet-go.tf`): Bird identification service on Proxmox storage
- **KegServe** (`kegserve.tf`): Rails-based personal keg management
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

2. **Check services**:
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
- **Purpose**: Protect sensitive infrastructure services (Traefik Dashboard, Longhorn UI)

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
