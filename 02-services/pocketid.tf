# Pocket ID OIDC Provider
resource "random_string" "pocketid_secret" {
  length  = 32
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Persistent Volume Claim for Pocket ID data
resource "kubernetes_manifest" "pocketid_pvc" {
  manifest = {
    apiVersion = "v1"
    kind       = "PersistentVolumeClaim"
    metadata = {
      name      = "pocketid-data"
      namespace = "default"
    }
    spec = {
      accessModes = ["ReadWriteOnce"]
      resources = {
        requests = {
          storage = "1Gi"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "pocketid_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "pocketid"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "pocketid"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "pocketid"
          }
        }
        spec = {
          containers = [{
            name  = "pocketid"
            image = "ghcr.io/pocket-id/pocket-id:v1.6.4"
            ports = [{
              containerPort = 1411
            }]
            env = [
              {
                name = "APP_URL"
                value = "https://pocketid.cdklein.com"
              },
              {
                name  = "DATABASE_PROVIDER"
                value = "sqlite"
              },
              {
                name  = "DATABASE_CONNECTION_STRING"
                value = "file:/app/data/pocket-id.db?_pragma=journal_mode(WAL)&_pragma=busy_timeout(2500)&_txlock=immediate"
              }
            ]
            volumeMounts = [{
              name      = "data"
              mountPath = "/app/data"
            }]
            livenessProbe = {
              httpGet = {
                path = "/healthz"
                port = 1411
              }
              initialDelaySeconds = 30
              periodSeconds       = 10
            }
            readinessProbe = {
              httpGet = {
                path = "/healthz"
                port = 1411
              }
              initialDelaySeconds = 5
              periodSeconds       = 5
            }
          }]
          volumes = [{
            name = "data"
            persistentVolumeClaim = {
              claimName = "pocketid-data"
            }
          }]
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.pocketid_pvc]
}

resource "kubernetes_manifest" "pocketid_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "pocketid"
      namespace = "default"
    }
    spec = {
      selector = {
        app = "pocketid"
      }
      ports = [{
        port       = 1411
        targetPort = 1411
        protocol   = "TCP"
      }]
      type = "ClusterIP"
    }
  }
}

# Let's Encrypt certificate for Pocket ID
resource "kubernetes_manifest" "pocketid_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "pocketid-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "pocketid-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["pocketid.cdklein.com"]
    }
  }
}

resource "kubernetes_manifest" "pocketid_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "pocketid-ingressroute"
      namespace = "default"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`pocketid.cdklein.com`)"
        kind  = "Rule"
        services = [{
          name = "pocketid"
          port = 1411
        }]
      }]
      tls = {
        secretName = "pocketid-tls"
      }
    }
  }
}

resource "technitium_dns_zone_record" "pocketid_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "pocketid.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.233"
}
