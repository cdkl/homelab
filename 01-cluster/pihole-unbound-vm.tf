# Pi-hole + Unbound DNS VM on Proxmox

resource "proxmox_vm_qemu" "dns_vm" {
  name        = "dns-vm"
  agent       = 1
  target_node = var.proxmox_node
  clone       = "ubuntu-24-04-template"

  os_type  = "cloud-init"
  cores    = 1
  memory   = 2048
  sockets  = 1
  onboot   = true
  startup  = "order=3"

  # Reuse existing cloud-init snippet that configures the user and SSH keys
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
    macaddr = "52:54:00:00:FA:01"
  }

  # Expect DHCP reservation to hand out 192.168.101.250
  ipconfig0 = "ip=dhcp"

  sshkeys = file(pathexpand(var.ssh_public_key_path))

  # Provision Pi-hole + Unbound using docker run (no compose)
  provisioner "remote-exec" {
    inline = [
      # Free port 53 and basic tooling
      "sudo systemctl disable --now systemd-resolved || true",
      "sudo rm -f /etc/resolv.conf || true",
      "echo -e 'nameserver 1.1.1.1\nnameserver 9.9.9.9' | sudo tee /etc/resolv.conf >/dev/null",
      "sudo apt-get update -y",
      "sudo apt-get install -y docker.io ca-certificates curl gnupg",

      # Folders
      "sudo mkdir -p /opt/pihole/etc-pihole /opt/pihole/etc-dnsmasq.d /opt/unbound/etc/unbound",

      # Unbound config (DoT to Cloudflare and Quad9)
      <<-EOCMD
sudo tee /opt/unbound/etc/unbound/unbound.conf >/dev/null <<'EOF'
server:
  verbosity: 0
  interface: 127.0.0.1
  port: 5335
  do-ip4: yes
  do-udp: yes
  do-tcp: yes
  prefer-ip6: no
  harden-dnssec-stripped: yes
  harden-referral-path: no
  use-caps-for-id: no
  edns-buffer-size: 1232
  prefetch: yes
  qname-minimisation: yes
  hide-identity: yes
  hide-version: yes
  tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt
  local-zone: "cdklein.com" transparent

forward-zone:
  name: "."
  forward-tls-upstream: yes
  forward-addr: 1.1.1.1@853#cloudflare-dns.com
  forward-addr: 9.9.9.9@853#dns.quad9.net
EOF
EOCMD
      ,

      # Restart containers idempotently
      "sudo docker rm -f unbound pihole 2>/dev/null || true",

      # Start Unbound (mount only config path to avoid overlaying binaries)
      "sudo docker run -d --name unbound --restart unless-stopped --network host -v /opt/unbound/etc/unbound/unbound.conf:/opt/unbound/etc/unbound/unbound.conf:ro mvance/unbound:latest",

      # Start Pi-hole
      "sudo docker run -d --name pihole --restart unless-stopped --network host -e TZ=UTC -e DNSMASQ_LISTENING=all -e PIHOLE_DNS_=127.0.0.1#5335 -e DNSSEC=true -e DNSMASQ_USER=root -e FTLCONF_LOCAL_IPV4=192.168.101.100 -e WEBPASSWORD=${var.pihole_admin_password} -v /opt/pihole/etc-pihole:/etc/pihole -v /opt/pihole/etc-dnsmasq.d:/etc/dnsmasq.d pihole/pihole:latest",
    ]

    connection {
      type        = "ssh"
      user        = var.proxmox_vm_user
      private_key = file(pathexpand(var.ssh_private_key_path))
      host        = self.ssh_host
    }
  }
}