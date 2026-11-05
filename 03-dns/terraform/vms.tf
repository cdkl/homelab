locals {
  nodes = {
    ns1 = {
      node = "bunker1"
      vmid = 107
      ip   = "192.168.101.239"
    }
    ns2 = {
      node = "bunker2"
      vmid = 108
      ip   = "192.168.101.240"
    }
  }
}

resource "proxmox_vm_qemu" "ns" {
  for_each = local.nodes

  name        = each.key
  vmid        = each.value.vmid
  agent       = 1
  target_node = each.value.node
  clone       = "ubuntu-24-04-template"
  full_clone  = true

  os_type  = "cloud-init"
  cores    = 1
  memory   = 2048
  sockets  = 1
  onboot   = true
  startup  = "order=3"

  cicustom  = "vendor=local:snippets/user-data.yml"
  ciupgrade = true

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
          size    = "16G"
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

  ipconfig0  = "ip=${each.value.ip}/24,gw=${var.gateway}"
  nameserver = var.nameserver
  sshkeys    = file(pathexpand(var.ssh_public_key_path))

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}

output "ns_ips" {
  value = { for k, v in proxmox_vm_qemu.ns : k => v.default_ipv4_address }
}
