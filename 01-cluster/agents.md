# Homelab Cluster Infrastructure (Stage 1)

> **Note**: This is part of a larger homelab infrastructure. See `../agents.md` for the complete overview.

## Current Directory: 01-cluster
This directory contains the core infrastructure deployment (Stage 1) that must be applied before any services in `02-services/`.

## What's Here
This stage provisions and configures:

### Core Infrastructure
- **K3s Cluster VMs** (`main.tf`): 1 master + 2 worker nodes on Proxmox
- **Technitium DNS Server** (`dns.tf`): Local DNS management with conditional forwarding
  - Primary zone for `cdklein.com` with local service records
  - Conditional forwarding to Cloudflare nameservers for domain validation
  - General DNS forwarding to Cloudflare public DNS (1.1.1.1, 1.0.0.1)
- **Cert-Manager** (`cert-manager.tf`): Let's Encrypt SSL with special DNS configuration
  - Custom DNS policy (`dnsPolicy: None`) to bypass cluster DNS
  - Direct querying of Cloudflare DNS (1.1.1.1, 1.0.0.1) for certificate validation
  - Cloudflare DNS-01 challenges for automated certificate issuance
- **MetalLB** (`metallb.tf`): Load balancer with IP pool 192.168.101.233-243
- **Longhorn Storage** (`longhorn.tf`): Distributed storage with NFS backup

### Required Variables
Create `localvars.auto.tfvars` with:
```hcl
proxmox_api_url = "https://your-proxmox-ip:8006/api2/json"
proxmox_api_token_id = "your-token-id"
proxmox_api_token_secret = "your-token-secret"
proxmox_node = "your-node-name"
proxmox_vm_user = "ubuntu"
ssh_public_key_path = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
technitium_admin_password = "secure-password"
cloudflare_api_token = "your-cloudflare-token"
acme_email = "your-email@domain.com"
```

### Deployment Order
1. Ensure Proxmox template `ubuntu-24-04-template` exists
2. Copy `cloud-init/user-data.yml` to Proxmox: `/var/lib/vz/snippets/`
3. Run standard Terraform workflow:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

### Post-Deployment
After successful apply:
1. **Get cluster access**:
   ```bash
   # Extract kubeconfig (shown in terraform output)
   ssh ubuntu@<master-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
   sed -i "s/127.0.0.1/<master-ip>/g" ~/.kube/config
   ```

2. **Verify cluster**:
   ```bash
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

3. **Check core services**:
   - Technitium DNS: http://192.168.101.233 (admin/your-password)
   - Longhorn UI: Should be accessible via kubectl port-forward initially

### Key Resources Created
- **VMs**: k3s-master, k3s-worker-1, k3s-worker-2
- **Namespaces**: dns, cert-manager, longhorn-system, metallb-system
- **LoadBalancer IPs**: 
  - 192.168.101.233 (Technitium DNS)
  - Pool 192.168.101.233-243 available for services
- **Storage Class**: longhorn (set as default)
- **ClusterIssuer**: letsencrypt-cloudflare

### Dependencies for Stage 2
Stage 2 services (`../02-services/`) depend on:
- Cluster being fully operational
- Technitium DNS service running and accessible
- MetalLB providing LoadBalancer services
- Longhorn storage available
- Cert-manager ready for certificate issuance

## DNS Architecture (Critical for Certificate Management)

This stage configures a sophisticated DNS setup that enables both local service resolution and reliable SSL certificate issuance:

### DNS Resolution Flow
1. **Cluster DNS (CoreDNS)** → forwards to Technitium DNS (192.168.101.243)
2. **Technitium DNS** processes queries:
   - **Local services**: Answered from local `cdklein.com` zone
   - **Domain validation**: Forwarded to Cloudflare nameservers via conditional forwarder
   - **External domains**: Forwarded to Cloudflare public DNS
3. **Cert-Manager**: Bypasses cluster DNS entirely, queries Cloudflare directly

### Why This Architecture?
The dual DNS approach solves a critical problem:
- **Local zone precedence** normally prevents DNS forwarding for the same domain
- **Cert-manager validation** requires access to Cloudflare's authoritative nameservers
- **Solution**: Give cert-manager direct access to Cloudflare DNS while maintaining local service resolution

**For detailed DNS troubleshooting and architecture diagrams**, see `../docs/dns-and-certificates.md`

### Troubleshooting
- **VM creation fails**: Check Proxmox template and network config
- **K3s installation fails**: Verify SSH keys and network connectivity
- **DNS service not accessible**: Check MetalLB IP assignment
- **Certificate issues**: 
  - Verify Cloudflare API token permissions
  - Check cert-manager pods have `dnsPolicy: None` in their spec
  - Test DNS resolution: `kubectl run dns-test --image=busybox --rm -it -- nslookup cdklein.com`
  - Monitor cert-manager logs: `kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager`

### Remote State
This stage stores state in PostgreSQL backend at `lorez.local:15432/terraform_cluster`. Stage 2 reads this state to get cluster information like master IP and storage class names.
