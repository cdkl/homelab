variable "proxmox_api_url" {
  type = string
}

variable "proxmox_api_token_id" {
  type = string
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "gateway" {
  type    = string
  default = "192.168.101.1"
}

variable "nameserver" {
  type    = string
  default = "1.1.1.1"
}
