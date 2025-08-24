# Homelab Scripts Directory

**Note**: This is part of a larger homelab infrastructure. See `../agents.md` for the complete overview.

## Overview
This directory contains utility scripts for managing homelab infrastructure operations. These scripts provide convenient interfaces for common administrative tasks that would otherwise require multiple kubectl or Terraform commands.

## Available Scripts

### tunnel-toggle.sh
**Purpose**: Comprehensive management script for Cloudflare Tunnel external access control.

**Location**: `scripts/tunnel-toggle.sh`

**Usage**:
```bash
./scripts/tunnel-toggle.sh [COMMAND]
```

**Commands**:
- `on` / `enable` / `start` - Turn tunnel ON (enable external access)
- `off` / `disable` / `stop` - Turn tunnel OFF (disable external access)
- `destroy` / `remove` - Completely destroy all tunnel resources
- `status` / `check` - Show current tunnel status and pod information
- `help` / `--help` / `-h` - Show detailed help information

**Features**:
1. **Smart Detection**: Automatically detects if tunnel deployment exists
2. **Multiple Methods**: Supports both kubectl scaling and Terraform resource management
3. **Status Monitoring**: Shows deployment status, replica counts, and pod readiness
4. **Error Handling**: Includes proper error checking and timeout handling
5. **Visual Feedback**: Color-coded output with emojis for easy status identification

#### Operation Methods

**Method 1: kubectl Scaling (Fastest)**
- Uses `kubectl scale deployment cloudflare-tunnel --replicas=X`
- Fastest method for on/off toggling
- Preserves all Kubernetes resources
- Recommended for regular enable/disable operations

**Method 2: Terraform Resource Management**
- Uses `terraform apply -var="tunnel_enabled=true/false"`
- Creates or destroys all tunnel-related resources
- Slower but more thorough
- Recommended for complete setup or teardown

#### Script Operation Flow

**Turn ON (`./tunnel-toggle.sh on`)**:
1. Checks if deployment exists
2. If exists: Scales to 1 replica and waits for readiness
3. If not exists: Creates resources via Terraform
4. Shows final status with metrics URL

**Turn OFF (`./tunnel-toggle.sh off`)**:
1. Checks if deployment exists
2. If exists: Scales to 0 replicas (immediate effect)
3. If not exists: Already off, shows status
4. Confirms tunnel is disabled

**Status Check (`./tunnel-toggle.sh status`)**:
1. Checks deployment existence and replica counts
2. Shows pod status and readiness
3. Displays metrics URL if tunnel is running
4. Provides clear visual indicators (✅ ON, ❌ OFF, ⚠️ Issues)

#### Output Examples

**Tunnel ON Status**:
```
🔍 Checking tunnel status...
✅ Tunnel is ON and running
NAME                               READY   STATUS    RESTARTS   AGE
cloudflare-tunnel-7b8f9d5c4-x2m8p   1/1     Running   0          2m15s

📊 Tunnel Metrics: https://tunnel-metrics.cdklein.com/metrics (TinyAuth required)
```

**Tunnel OFF Status**:
```
🔍 Checking tunnel status...
❌ Tunnel is OFF (scaled to 0)
```

#### Integration with Homelab Infrastructure

**Dependencies**:
- Requires kubectl access to the K3s cluster
- Needs Terraform working directory at `../02-services/`
- Depends on Cloudflare Tunnel resources being deployed

**Related Services**:
- **Cloudflare Tunnel Deployment**: Managed Kubernetes deployment
- **Tunnel Metrics Service**: Internal monitoring at tunnel-metrics.cdklein.com
- **TinyAuth Integration**: Metrics endpoint protected by SSO

**External Services Controlled**:
When tunnel is ON, these services become externally accessible:
- `https://foundryvtt.cdklein.com` - Virtual tabletop (TinyAuth protected)
- `https://auth.cdklein.com` - Authentication portal
- `https://pocketid.cdklein.com` - OAuth provider (if deployed)
- `https://static.cdklein.com` - Static assets server

#### Quick Reference Commands

**Direct kubectl Commands**:
```bash
# Turn ON (scale to 1 replica)
kubectl scale deployment cloudflare-tunnel --replicas=1

# Turn OFF (scale to 0 replicas)  
kubectl scale deployment cloudflare-tunnel --replicas=0

# Check status
kubectl get deployment cloudflare-tunnel
kubectl get pods -l app=cloudflare-tunnel
```

**Direct Terraform Commands**:
```bash
# Create tunnel resources
cd 02-services && terraform apply -var="tunnel_enabled=true"

# Destroy tunnel resources
cd 02-services && terraform apply -var="tunnel_enabled=false"
```

#### Troubleshooting

**Common Issues**:
1. **Script can't find kubectl**: Ensure kubectl is in PATH and kubeconfig is configured
2. **Terraform not found**: Ensure script runs from homelab root or 02-services directory
3. **Pod not ready**: Check Cloudflare tunnel token validity and network connectivity
4. **Metrics not accessible**: Verify TinyAuth is running and certificates are valid

**Debug Commands**:
```bash
# Check pod logs
kubectl logs -l app=cloudflare-tunnel --tail=20

# Check tunnel token (if using tunnel-secrets)
kubectl get secret tunnel-token -o yaml

# Verify metrics service
kubectl get svc cloudflare-tunnel-metrics
curl -I https://tunnel-metrics.cdklein.com/metrics
```

## Security Considerations

### Script Security
- **Error Handling**: Uses `set -e` for fail-fast behavior
- **Path Security**: Uses absolute paths to prevent directory traversal
- **Input Validation**: Validates command arguments with case statements
- **Secret Handling**: Never exposes sensitive tokens in output or logs

### Tunnel Security
- **No Open Ports**: Tunnel doesn't require opening firewall ports
- **Encrypted Traffic**: All traffic encrypted through Cloudflare network
- **Access Control**: External services still require TinyAuth authentication
- **Token-based Auth**: Uses Cloudflare tunnel tokens instead of certificate files

## Future Script Ideas

**Potential Additions**:
1. **backup-longhorn.sh** - Manual Longhorn backup triggering
2. **cert-renewal.sh** - Force certificate renewal for debugging
3. **service-restart.sh** - Systematic service restart with dependency awareness
4. **cluster-health.sh** - Comprehensive cluster health checking
5. **log-collector.sh** - Centralized log collection for troubleshooting

## Usage Patterns

### Regular Operations
```bash
# Enable external access for gaming session
./scripts/tunnel-toggle.sh on

# Disable external access after session
./scripts/tunnel-toggle.sh off

# Quick status check
./scripts/tunnel-toggle.sh status
```

### Maintenance Operations
```bash
# Complete tunnel teardown for maintenance
./scripts/tunnel-toggle.sh destroy

# Recreate tunnel after maintenance
cd 02-services && terraform apply -var="tunnel_enabled=true"
```

### Monitoring Operations
```bash
# Check tunnel status and metrics
./scripts/tunnel-toggle.sh status

# Access metrics (requires browser for TinyAuth)
open https://tunnel-metrics.cdklein.com/metrics
```

## Integration with CI/CD

The scripts are designed to be CI/CD friendly:
- **Exit Codes**: Proper exit codes for success/failure
- **Logging**: Structured output suitable for log aggregation  
- **Idempotent**: Safe to run multiple times
- **Automated**: Can be triggered by external systems or schedules

## Contributing

When adding new scripts:
1. Follow the established pattern of help text and error handling
2. Use consistent emoji and formatting for output
3. Include proper parameter validation
4. Add documentation to this agents.md file
5. Test scripts in both success and failure scenarios
