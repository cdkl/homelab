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
        macaddr = "52:54:00:00:00:10"  # Unique MAC for FoundryVTT
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
