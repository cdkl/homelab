# Manage local cdklein.com host records on Pi-hole via ssh + dnsmasq host-records

variable "pihole_vm_user" {
  description = "SSH user for the Pi-hole VM"
  type        = string
  default     = "bunker"
}

variable "pihole_ssh_private_key_path" {
  description = "Path to SSH private key used to reach the Pi-hole VM"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "pihole_local_hosts" {
  description = "Map of FQDN => IPv4 to publish locally in Pi-hole"
  type        = map(string)
  default = {
    "pihole.cdklein.com"   = "192.168.101.100"
    "traefik.cdklein.com"  = "192.168.101.233"
    "longhorn.cdklein.com" = "192.168.101.233"
  }
}

variable "pihole_vm_host" {
  description = "Hostname or IP of the Pi-hole VM"
  type        = string
  default     = "192.168.101.100"
}

locals {
  pihole_hosts_conf = templatefile("${path.module}/templates/pihole-hosts.tpl", {
    hosts = var.pihole_local_hosts
  })
}

resource "null_resource" "pihole_local_dns" {
  triggers = {
    conf_sha = sha1(local.pihole_hosts_conf)
    host     = var.pihole_vm_host
  }

  connection {
    type        = "ssh"
    user        = var.pihole_vm_user
    private_key = file(pathexpand(var.pihole_ssh_private_key_path))
    host        = var.pihole_vm_host
  }

  provisioner "remote-exec" {
    inline = [
      # Write the dnsmasq host-records config and reload Pi-hole
      "sudo mkdir -p /opt/pihole/etc-dnsmasq.d",
      "cat > /tmp/10-local-hosts.conf <<'EOF'\n${replace(local.pihole_hosts_conf, "\n", "\\n")}\nEOF",
      "sudo mv /tmp/10-local-hosts.conf /opt/pihole/etc-dnsmasq.d/10-local-hosts.conf",
      "sudo docker exec pihole pihole reloadlists || sudo docker exec pihole pihole reloaddns || sudo docker restart pihole"
    ]
  }
}
