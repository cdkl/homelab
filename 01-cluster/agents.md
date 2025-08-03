# Homelab Cluster Infrastructure (Stage 1)

> **Note**: This is part of a larger homelab infrastructure. See `../agents.md` for the complete overview.

## Current Directory: 01-cluster
This directory contains the core infrastructure deployment (Stage 1) that must be applied before any services in `02-services/`.

## What's Here
This stage provisions and configures:

### Core Infrastructure
- **K3s Cluster VMs** (`main.tf`): 1 master + 2 worker nodes on Proxmox
- **Technitium DNS Server** (`dns.tf`): Local DNS management for cdklein.com
- **Cert-Manager** (`cert-manager.tf`): Let's Encrypt SSL with Cloudflare DNS-01
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

### Troubleshooting
- **VM creation fails**: Check Proxmox template and network config
- **K3s installation fails**: Verify SSH keys and network connectivity
- **DNS service not accessible**: Check MetalLB IP assignment
- **Certificate issues**: Verify Cloudflare API token permissions

### Remote State
This stage stores state in PostgreSQL backend at `lorez.local:15432/terraform_cluster`. Stage 2 reads this state to get cluster information like master IP and storage class names.
