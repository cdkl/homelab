output "k3s_master_ip" {
  description = "IP address of the k3s master node"
  value       = proxmox_vm_qemu.k3s-master.default_ipv4_address
}

output "dns_vm_ip" {
  description = "IP address of the Pi-hole DNS VM"
  value       = proxmox_vm_qemu.dns_vm.default_ipv4_address
}
