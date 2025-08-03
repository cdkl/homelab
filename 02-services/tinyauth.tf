locals {
  tinyauth_users = join(",", [for user_map in var.tinyauth_users_list : "${user_map.user}:${user_map.hash}"])
}

resource "random_string" "tinyauth_secret" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

resource "kubernetes_manifest" "tinyauth_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "tinyauth"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "tinyauth"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "tinyauth"
          }
        }
        spec = {
          containers = [{
            name  = "tinyauth"
            image = "ghcr.io/steveiliop56/tinyauth:v3"
            ports = [{
              containerPort = 3000
            }]
            env = [
              {
                name  = "SECRET"
                value = random_string.tinyauth_secret.result
              },
              {
                name  = "APP_URL"
                value = "https://auth.cdklein.com"
              },
              {
                name  = "USERS"
                value = local.tinyauth_users
              },
              {
                name  = "COOKIE_SECURE"
                value = "true"
              },
              {
                name  = "SESSION_EXPIRY"
                value = "604800"
              },
              {
                name  = "BACKGROUND_IMAGE"
                value = "https://static.cdklein.com/background.jpg"
              }
            ]
          }]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "tinyauth_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "tinyauth"
      namespace = "default"
    }
    spec = {
      selector = {
        app = "tinyauth"
      }
      ports = [{
        port       = 3000
        targetPort = 3000
        protocol   = "TCP"
      }]
      type = "ClusterIP"
    }
  }
}

# Let's Encrypt certificate for tinyauth
resource "kubernetes_manifest" "tinyauth_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "tinyauth-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "tinyauth-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["auth.cdklein.com"]
    }
  }
}

resource "kubernetes_manifest" "tinyauth_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "tinyauth-ingressroute"
      namespace = "default"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`auth.cdklein.com`)"
        kind  = "Rule"
        services = [{
          name = "tinyauth"
          port = 3000
        }]
      }]
      tls = {
        secretName = "tinyauth-tls"
      }
    }
  }
}

resource "technitium_dns_zone_record" "auth_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "auth.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.234"
}
