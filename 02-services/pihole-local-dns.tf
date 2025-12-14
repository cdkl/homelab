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
  master_ip     = try(data.terraform_remote_state.cluster.outputs.k3s_master_ip, "192.168.101.185")
  foundry_ip    = try(data.terraform_remote_state.cluster.outputs.foundryvtt_ip, null)

  merged_hosts = merge(
    var.pihole_local_hosts,
    {
      "birdnet-go.cdklein.com" = local.master_ip,
      "kegserve.cdklein.com"   = local.master_ip,
      "pocketid.cdklein.com"   = "192.168.101.233",
      "auth.cdklein.com"       = "192.168.101.233",
      "static.cdklein.com"     = "192.168.101.233",
      "tunnel-metrics.cdklein.com" = "192.168.101.233",
      # Legacy hosts from prior Technitium zone
      "homeassistant.cdklein.com" = "192.168.101.77",
      "hunkerbunker.cdklein.com"  = "192.168.101.77",
      "brewpi.cdklein.com"        = "192.168.101.14",
      "lorez.cdklein.com"         = "192.168.101.2",
      "birdnet.cdklein.com"       = "192.168.101.172",
      "bunker1.cdklein.com"       = "192.168.101.33"
    },
    local.foundry_ip == null ? {} : { "foundryvtt.cdklein.com" = local.foundry_ip }
  )

  cnames = {
    "proxmoxbox.cdklein.com" = "bunker1.cdklein.com"
  }

  # Build Pi-hole v6 hosts and CNAME arrays (HOSTS format strings)
  hosts_array = [for name, ip in local.merged_hosts : "${ip} ${name}"]
  cname_array = [for alias, target in local.cnames : "${alias} ${target}"]

  hosts_json = jsonencode(local.hosts_array)
  cname_json = jsonencode(local.cname_array)
}

resource "null_resource" "pihole_local_dns" {
  triggers = {
    conf_sha = sha1("${local.hosts_json}|${local.cname_json}")
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
      # Configure Pi-hole v6 local DNS via pihole-FTL (dns.hosts and dns.cnameRecords)
      "sudo docker exec pihole pihole-FTL --config dns.hosts '${local.hosts_json}'",
      "sudo docker exec pihole pihole-FTL --config dns.cnameRecords '${local.cname_json}'",
      # Reload DNS
      "sudo docker exec pihole pihole reloaddns || sudo docker restart pihole"
    ]
  }
}
