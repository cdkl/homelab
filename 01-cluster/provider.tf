terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc6"
    }
  }
}

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

provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_api_token_id = var.proxmox_api_token_id
  pm_api_token_secret    = var.proxmox_api_token_secret
  pm_tls_insecure = true  # Change to false if using a valid SSL certificate
}

provider "helm" {
    kubernetes {
        config_path = "~/.kube/config"
    }
}


