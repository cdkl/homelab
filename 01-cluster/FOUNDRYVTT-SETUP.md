# FoundryVTT VM Setup Instructions

This document provides step-by-step instructions for setting up the FoundryVTT VM using Terraform and Proxmox VE.

## Prerequisites

1. **Proxmox VE** with `ubuntu-24-04-template` available
2. **Terraform** installed and configured for your Proxmox environment
3. **SSH keys** set up for VM access
4. **Stage 1 infrastructure** (your K3s cluster) should be deployed first

## Files Created

- `foundryvtt.tf` - Terraform configuration for the VM
- `cloud-init/foundryvtt-user-data.yml` - Cloud-init configuration
- `FOUNDRYVTT-SETUP.md` - This instruction file

## Step 1: Upload Cloud-Init File to Proxmox

The cloud-init file needs to be uploaded to your Proxmox server's snippets directory.

```bash
# Copy the cloud-init file to your Proxmox server
scp ./cloud-init/foundryvtt-user-data.yml root@YOUR_PROXMOX_IP:/var/lib/vz/snippets/

# Or if you prefer, use the Proxmox web interface:
# 1. Go to your Proxmox node > local > Content
# 2. Upload the foundryvtt-user-data.yml file to the "snippets" content type
```

## Step 2: Deploy with Terraform

From the `01-cluster` directory:

```bash
# Initialize Terraform (if not already done)
terraform init

# Plan the deployment (to see what will be created)
terraform plan

# Apply the configuration
terraform apply
```

The deployment will:
1. Create a new VM called `foundryvtt`
2. Configure it with 2 cores, 4GB RAM, 32GB storage
3. Install Node.js 18.x LTS
4. Set up the FoundryVTT user and directories
5. Install nginx and certbot for SSL
6. Create systemd service files
7. Run the setup script to show next steps

## Step 3: Verify VM Creation

After Terraform completes, you should see output like:

```
foundryvtt_ip = "192.168.101.XXX"
foundryvtt_ssh_command = "ssh ubuntu@192.168.101.XXX"
```

## Step 4: Connect and Verify Setup

```bash
# Use the SSH command from Terraform output
ssh ubuntu@192.168.101.XXX

# Run the setup script to see current status
./setup-foundryvtt.sh
```

You should see output confirming:
- Node.js and NPM versions
- FoundryVTT user created
- Directory structure in place
- PM2 installed globally

## VM Specifications

- **Name**: `foundryvtt`
- **Template**: `ubuntu-24-04-template`
- **CPU**: 2 cores
- **Memory**: 4GB
- **Storage**: 32GB
- **Network**: vmbr0 bridge, DHCP
- **MAC Address**: `52:54:00:00:00:10`
- **Boot Order**: 3 (after K3s cluster)

## What Gets Installed

The cloud-init configuration installs and configures:

### System Packages
- qemu-guest-agent
- curl, wget, unzip
- nginx
- certbot and python3-certbot-nginx

### Node.js Environment
- Node.js 18.x LTS (latest stable)
- NPM (comes with Node.js)
- PM2 process manager (globally)

### FoundryVTT Setup
- User: `foundryvtt`
- App Directory: `/opt/foundryvtt/app/`
- Data Directory: `/opt/foundryvtt/data/`
- Systemd service: `/etc/systemd/system/foundryvtt.service`
- Nginx config: `/etc/nginx/sites-available/foundryvtt`

### Helper Scripts
- `/home/ubuntu/setup-foundryvtt.sh` - Status and next steps

## Next Steps After VM Creation

1. **Download FoundryVTT**: Get the Node.js version from your FoundryVTT account
2. **Transfer Data**: Copy your existing FoundryVTT data from Kubernetes
3. **Install FoundryVTT**: Extract and set up the application
4. **Configure SSL**: Set up Let's Encrypt certificates
5. **Update DNS**: Point your domain to the new VM IP
6. **Start Service**: Enable and start the FoundryVTT systemd service

See the main transition documentation for detailed steps on data migration and FoundryVTT installation.

## Troubleshooting

### VM Won't Start
- Check that `ubuntu-24-04-template` exists in Proxmox
- Verify sufficient resources (CPU, memory, storage) available
- Check Proxmox logs for VM creation issues

### Cloud-Init Issues
- Verify `foundryvtt-user-data.yml` is in `/var/lib/vz/snippets/`
- Check cloud-init logs: `sudo cat /var/log/cloud-init-output.log`
- Validate YAML syntax in the cloud-init file

### SSH Connection Issues
- Wait a few minutes for cloud-init to complete
- Check VM console in Proxmox web interface
- Verify SSH keys are correctly configured

### Node.js Installation Issues
- Check if NodeSource repository was added correctly
- Verify internet connectivity from the VM
- Check apt update/upgrade logs

## Integration with Stage 2

The VM IP address is exported as `foundryvtt_ip` and can be referenced in Stage 2 for:
- DNS record updates
- Firewall configurations
- Monitoring setup

Update your Stage 2 DNS configuration to use this output instead of the Kubernetes service IP.
