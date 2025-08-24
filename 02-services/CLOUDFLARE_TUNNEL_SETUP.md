# Cloudflare Tunnel Setup for External FoundryVTT Access

This guide will help you set up a Cloudflare Tunnel to allow external users to access your FoundryVTT server and authentication services securely.

## Prerequisites

1. **Cloudflare Account**: You need a Cloudflare account with a domain managed by Cloudflare
2. **Domain**: A public domain that you want to use for external access (e.g., `yourdomain.com`)
3. **Cloudflare Tunnel**: Access to Cloudflare Zero Trust dashboard

## Step 1: Create a Cloudflare Tunnel

### 1.1 Access Cloudflare Zero Trust Dashboard
1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Select your account
3. Navigate to **Access** → **Tunnels**

### 1.2 Create a New Tunnel
1. Click **Create a tunnel**
2. Choose **Cloudflared** as the connector type
3. Name your tunnel: `homelab-tunnel` (or any name you prefer)
4. Click **Save tunnel**

### 1.3 Get the Tunnel Token
1. After creating the tunnel, you'll see installation instructions
2. Copy the tunnel token from the command - it looks like:
   ```
   eyJ... (very long string)
   ```
3. **Important**: Save this token securely - you'll need it for your Terraform configuration

## Step 2: Configure Terraform Variables

Add the following variable to your `terraform.tfvars` file:

```hcl
# Cloudflare Tunnel Configuration
cloudflare_tunnel_token = "your-tunnel-token-here"
```

**Replace**:
- `your-tunnel-token-here` with the token from Step 1.3

**Note**: The external domain defaults to `cdklein.com` since you already own and control this domain. No need to specify `external_domain` unless you want to use a different domain.

## Step 3: Deploy the Tunnel

Apply the Terraform configuration:

```bash
terraform plan
terraform apply
```

This will create:
- Cloudflare tunnel deployment in Kubernetes
- Configuration for routing external traffic
- Metrics service for monitoring

## Step 4: Configure DNS Records in Cloudflare

### 4.1 Automatic Configuration (Recommended)
After the tunnel is running, configure the DNS records in the Cloudflare dashboard:

1. Go to **Cloudflare Dashboard** → **DNS** → **Records**
2. Add CNAME records for each service:
   - **Name**: `foundryvtt`, **Target**: `your-tunnel-id.cfargotunnel.com`
   - **Name**: `auth`, **Target**: `your-tunnel-id.cfargotunnel.com`
   - **Name**: `pocketid`, **Target**: `your-tunnel-id.cfargotunnel.com`
   - **Name**: `static`, **Target**: `your-tunnel-id.cfargotunnel.com`

### 4.2 Alternative: CLI Configuration
You can also use the `cloudflared` CLI to configure DNS:

```bash
# Install cloudflared locally
# Then configure each hostname
cloudflared tunnel route dns homelab-tunnel foundryvtt.yourdomain.com
cloudflared tunnel route dns homelab-tunnel auth.yourdomain.com
cloudflared tunnel route dns homelab-tunnel pocketid.yourdomain.com
cloudflared tunnel route dns homelab-tunnel static.yourdomain.com
```

## Step 5: Update Service Configurations

### 5.1 Update TinyAuth Configuration
Update the TinyAuth configuration to work with the external domain. You'll need to modify the `APP_URL` in the TinyAuth deployment:

```bash
# This will be done automatically if you update the tinyauth.tf file
# to use the external domain for APP_URL
```

### 5.2 Update PocketID Redirect URIs
In your PocketID OIDC client configuration, add the external redirect URI:
- `https://auth.yourdomain.com/api/oauth/callback/generic`

## Step 6: Test External Access

### 6.1 Check Tunnel Status
```bash
# Check if tunnel is running
kubectl get pods -l app=cloudflare-tunnel

# Check tunnel logs
kubectl logs -l app=cloudflare-tunnel
```

### 6.2 Test Services
Try accessing each service externally:
1. **FoundryVTT**: `https://foundryvtt.cdklein.com`
2. **Authentication**: `https://auth.cdklein.com`
3. **PocketID**: `https://pocketid.cdklein.com`

### 6.3 Test Authentication Flow
1. Visit `https://foundryvtt.cdklein.com`
2. Should redirect to `https://auth.cdklein.com`
3. Login with PocketID should work
4. Should redirect back to FoundryVTT

## Services Exposed Externally

The tunnel exposes these services for external access:

| Service | Internal URL | External URL |
|---------|-------------|--------------|
| FoundryVTT | `http://foundryvtt-service:30000` | `https://foundryvtt.cdklein.com` |
| TinyAuth | `http://tinyauth:3000` | `https://auth.cdklein.com` |
| PocketID | `http://pocketid:1411` | `https://pocketid.cdklein.com` |
| Static Assets | `http://static-assets:80` | `https://static.cdklein.com` |

## Security Considerations

- **HTTPS Only**: All external traffic is automatically encrypted via Cloudflare
- **No Open Ports**: No firewall ports need to be opened on your network
- **Authentication Required**: FoundryVTT requires authentication via TinyAuth/PocketID
- **DDoS Protection**: Cloudflare provides DDoS protection automatically
- **Access Control**: Consider setting up Cloudflare Access rules for additional security

## Troubleshooting

### Common Issues

1. **Tunnel Not Connecting**
   - Check tunnel token is correct
   - Verify tunnel deployment is running: `kubectl get pods -l app=cloudflare-tunnel`
   - Check logs: `kubectl logs -l app=cloudflare-tunnel`

2. **DNS Not Resolving**
   - Verify DNS records are created in Cloudflare
   - Wait for DNS propagation (up to 48 hours)
   - Test with `dig foundryvtt.yourdomain.com`

3. **Authentication Issues**
   - Ensure PocketID OIDC client has correct redirect URIs
   - Check TinyAuth configuration for external domain
   - Verify all auth services are accessible

4. **503 Service Unavailable**
   - Check that internal services are running
   - Verify service names and ports in tunnel configuration
   - Check Kubernetes service endpoints

### Monitoring Commands

```bash
# Check tunnel status
kubectl get deployment cloudflare-tunnel
kubectl get pods -l app=cloudflare-tunnel

# View tunnel logs
kubectl logs -l app=cloudflare-tunnel -f

# Check tunnel metrics (if enabled)
kubectl port-forward svc/cloudflare-tunnel-metrics 2000:2000
# Then visit http://localhost:2000/metrics
```

## Next Steps

Once the tunnel is working:
1. Test with external users
2. Consider setting up Cloudflare Access policies for additional security
3. Monitor tunnel usage and performance
4. Set up alerting for tunnel connectivity issues

Your FoundryVTT server should now be accessible to external users while maintaining security through authentication!
