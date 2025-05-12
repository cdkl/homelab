# Homelab Infrastructure as Code

This repository contains Terraform configurations for managing a homelab infrastructure using Proxmox VE, focusing on K3s cluster deployment.

## Current Features

- Provisions K3s cluster on Proxmox VE:
  - 1 master node
  - 2 worker nodes
- Uses cloud-init for VM initialization
- Configures networking with DHCP
- Automatically installs and configures K3s cluster

## Prerequisites

- Proxmox VE server
- Terraform installed
- SSH key pair
- Ubuntu 24.04 cloud-init template on Proxmox
- DHCP server

## Configuration

1. Create a `localvars.auto.tfvars` file with your Proxmox credentials:
```tfvars
proxmox_api_url = "https://your-proxmox-ip:8006/api2/json"
proxmox_api_token_id = "your-token-id"
proxmox_api_token_secret = "your-token-secret"
proxmox_node = "your-node-name"
```

2. Ensure your SSH public key is available at `~/.ssh/id_rsa.pub`

## Cloud-Init Configuration

1. Copy the user-data.yml snippet to Proxmox server where it will be applied during cloud-init:
```powershell
# Create snippets directory on Proxmox (if it doesn't exist)
ssh root@<proxmox-ip> "mkdir -p /var/lib/vz/snippets"

# Copy user-data.yml to Proxmox
scp cloud-init/user-data.yml root@<proxmox-ip>:/var/lib/vz/snippets/
```

2. Verify the file exists on Proxmox:
```bash
ssh root@<proxmox-ip> "ls -l /var/lib/vz/snippets/user-data.yml"
```

The Terraform configuration will reference this file using:
```hcl
cicustom = "user=local:snippets/user-data.yml"
```

## Usage

```bash
# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Apply the configuration
terraform apply
```

## Cluster Details

- Master Node:
  - 2 CPU cores
  - 4GB RAM
  - 20GB storage

- Worker Nodes (x2):
  - 2 CPU cores each
  - 3GB RAM each
  - 20GB storage each

## Post-Deployment

After deployment, you can access your cluster using:

```bash
# Copy kubeconfig from master node
ssh ubuntu@<master-ip> "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config

# Replace server address in kubeconfig
sed -i "s/127.0.0.1/<master-ip>/g" ~/.kube/config

# Verify cluster status
kubectl get nodes
```

## Accessing Traefik Dashboard

The Traefik dashboard is available at `http://traefik.local/dashboard/` or through your cluster IP.

1. Add DNS record or edit your hosts file:
```bash
echo "192.168.101.xxx traefik.local" | sudo tee -a /etc/hosts
```

2. Default credentials:
- Username: admin
- Password: changeme

**Important**: Change the default password in `kubernetes/traefik-dashboard.yaml` before applying.

## Security Notes

- Never commit sensitive information like API tokens to version control
- The kubeconfig file contains sensitive cluster access information
- Default user is 'ubuntu' with SSH key authentication
