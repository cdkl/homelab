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

resource "kubernetes_manifest" "traefik_dashboard_config" {
    manifest = yamldecode(file("${path.module}/kubernetes/traefik-dashboard-config.yaml"))

    depends_on = [
        proxmox_vm_qemu.k3s-master
    ]
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

# Output worker nodes IPs
output "worker_ips" {
  value = proxmox_vm_qemu.k3s-worker[*].default_ipv4_address
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
}

resource "kubernetes_service" "birdnet_go_service" {
  metadata {
    name = "birdnet-go-service"
  }

  spec {
    selector = {
      app = "birdnet-go" # Ensure this matches the labels of your Pod/Deployment
    }

    port {
      port        = 8080       # Port exposed by the Service
      target_port = 8080       # Port on the container
      protocol    = "TCP"
    }

    type = "LoadBalancer"      # Exposes the Service externally
  }

  depends_on = [
    kubernetes_pod.birdnet_go  
]
}


# resource "kubernetes_manifest" "traefik-dashboard-config" {
#     manifest = yamldecode(file("${path.module}/kubernetes/traefik-dashboard-config.yaml"))

#     depends_on = [
#         proxmox_vm_qemu.k3s-master,
#         proxmox_vm_qemu.k3s-worker
#     ]
# }

# resource "kubernetes_manifest" "traefik_dashboard_service" {
#   manifest = yamldecode(file("${path.module}/kubernetes/traefik-dashboard-service.yaml"))

#   depends_on = [
#     proxmox_vm_qemu.k3s-master,
#     proxmox_vm_qemu.k3s-worker
#   ]
# }

resource "kubernetes_pod" "birdnet_go" {
    metadata {
        name = "birdnet-go"
        labels = {
            app = "birdnet-go"
        }
    }

    spec {
        container {
            name  = "birdnet-go"
            image = "ghcr.io/tphakala/birdnet-go:nightly"

            port {
                container_port = 8080
                name          = "http"
            }

            resources {
                requests = {
                    memory = "256Mi"
                    cpu    = "500m"
                }
                limits = {
                    memory = "512Mi"
                    cpu    = "2"
                }
            }

            volume_mount {
                name       = "config-volume"
                mount_path = "/config"
            }

            volume_mount {
                name       = "data-volume"
                mount_path = "/data"
            }
        }

        volume {
            name = "config-volume"

            host_path {
                path = "/mnt/pve/nfs/birdnet-go-config"
            }
        }

        volume {
            name = "data-volume"

            host_path {
                path = "/mnt/pve/nfs/birdnet-go-data"
            }
        }
    }

  depends_on = [
        proxmox_vm_qemu.k3s-master,
        proxmox_vm_qemu.k3s-worker
]

}

output "birdnet_go_pod_name" {
    value = kubernetes_pod.birdnet_go.metadata[0].name
}


# resource "proxmox_vm_qemu" "home_assistant" {
#     name        = "home-assistant"
#     target_node = var.proxmox_node
#     agent       = 1

#     # Resource allocation
#     cores    = 2
#     memory   = 2048
#     sockets  = 1
#     scsihw   = "virtio-scsi-single"

#     # Import the QCOW2 disk
#     disks {
#         scsi {
#             scsi0 {
#                 disk {
#                     import_from = "/var/lib/vz/template/iso/haos_ova-10.5.qcow2"
#                     size    = "32G"
#                     storage = "local-lvm"
#                 }
#             }
#         }
#     }

#     network {
#         id     = 0
#         model  = "virtio"
#         bridge = "vmbr0"
#     }

#     ipconfig0 = "ip=dhcp"

#     # No cloud-init for Home Assistant OS
#     os_type = "other"
# }

# # Output Home Assistant IP
# output "home_assistant_ip" {
#   value = proxmox_vm_qemu.home_assistant.default_ipv4_address
# }
