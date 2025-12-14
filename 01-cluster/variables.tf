variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type = string
}

variable "proxmox_node" {
  type        = string
  description = "The node name of the Proxmox server"
}

variable "proxmox_vm_user" {
  type        = string
  description = "The username to use for the VMs"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for DNS-01 challenges"
  type        = string
  sensitive   = true
}

variable "acme_email" {
  description = "Email address for ACME/Let's Encrypt certificate registration"
  type        = string
  sensitive   = true
}

variable "pihole_admin_password" {
  description = "Admin password for Pi-hole web UI"
  type        = string
  sensitive   = true
}
