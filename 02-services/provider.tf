terraform {
  required_providers {
        technitium = {
      version = "~> 0.2.0"
      source = "registry.terraform.io/kenske/technitium"
    }
  }
}

provider "helm" {
    kubernetes {
        config_path = "~/.kube/config"
    }
}

provider "technitium" {
  host  = "http://dns.cdklein.com"
  username = "admin"
  password = data.terraform_remote_state.cluster.outputs.technitium_admin_password
}
