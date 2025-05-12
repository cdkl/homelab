resource "random_string" "k3s_secret" {
  length = 40
  special = false
}

resource "proxmox_vm_qemu" "k3s-master" {
    name        = "k3s-master"
    agent = 1
    target_node = var.proxmox_node
    clone = "ubuntu-24-04-template"  # Ensure you have this template

    os_type  = "cloud-init"
    cores    = 2
    memory   = 4096
    sockets  = 1

    # Cloud-Init configuration
    cicustom   = "vendor=local:snippets/user-data.yml" # /var/lib/vz/snippets/user-data.yml
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
                    size = "20G"
                    storage = "local-lvm"
                }
            }
        }
    }

    network {
        id = 0
        model  = "virtio"
        bridge = "vmbr0"
        macaddr = "52:54:00:00:00:01"  # Using KVM/QEMU recommended prefix
    }

    ipconfig0 = "ip=dhcp"

    sshkeys = <<EOF
      ${file("~/.ssh/id_rsa.pub")}
    EOF

    provisioner "remote-exec" {

        inline = [  
            "curl -L https://get.k3s.io | K3S_TOKEN=${random_string.k3s_secret.result} sh -",
            "sudo systemctl enable --now k3s",
        ]  

        connection {
            type        = "ssh"
            user        = var.proxmox_vm_user
            private_key = file("~/.ssh/id_rsa")
            host        = self.ssh_host
        }
    }

    provisioner "local-exec" {
        # This only works on windows, sorry
        command = "ssh -o StrictHostKeyChecking=no ${var.proxmox_vm_user}@${self.ssh_host} sudo cat /etc/rancher/k3s/k3s.yaml | % { $_ -replace '127.0.0.1', '${self.ssh_host}' } > ~/.kube/config ; kubectl config set-context default"
        interpreter = [ "powershell", "-Command" ]
    }

    # provisioner "local-exec" {
    #     command = "cat ~/.kube/config | % { $_ -replace '127.0.0.1', '${self.ssh_host}' } > ~/.kube/config"
    #     interpreter = [ "powershell", "-Command" ]
    # }
}

output "kubeconfig_command" {
  value = "ssh ${var.proxmox_vm_user}@${proxmox_vm_qemu.k3s-master.default_ipv4_address} 'sudo cat /etc/rancher/k3s/k3s.yaml'"
}

resource "proxmox_vm_qemu" "k3s-worker" {
    count       = 2
    name        = "k3s-worker-${count.index + 1}"
    target_node = var.proxmox_node
    clone       = "ubuntu-24-04-template"
    agent       = 1

    # Resource allocation
    os_type = "cloud-init"
    cores    = 2
    memory   = 3072
    sockets  = 1
    scsihw   = "virtio-scsi-single"

    # Cloud-Init configuration
    cicustom   = "vendor=local:snippets/user-data.yml" # /var/lib/vz/snippets/user-data.yml
    ciupgrade  = true

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
                    size    = "20G"
                    storage = "local-lvm"
                }
            }
        }
    }

    network {
        id     = 0
        model  = "virtio"
        bridge = "vmbr0"
        macaddr = "52:54:00:00:00:0${count.index + 2}"  # Using KVM/QEMU recommended prefix
    }

    ipconfig0 = "ip=dhcp"

    sshkeys = <<EOF
        ${file("~/.ssh/id_rsa.pub")}
    EOF

    # Use the retrieved token for worker node setup
    provisioner "remote-exec" {
        inline = [
            "curl -sfL https://get.k3s.io | K3S_URL=https://${proxmox_vm_qemu.k3s-master.default_ipv4_address}:6443 K3S_TOKEN=${random_string.k3s_secret.result} sh -"
        ]

        connection {
            type        = "ssh"
            user        = var.proxmox_vm_user
            private_key = file("~/.ssh/id_rsa")
            host        = self.ssh_host
        }
    }
}

# output master node IPs
output "master_ip" {
  value = proxmox_vm_qemu.k3s-master.default_ipv4_address
}

# Output worker nodes IPs
output "worker_ips" {
  value = proxmox_vm_qemu.k3s-worker[*].default_ipv4_address
}



