# FoundryVTT Self-hosted Virtual Tabletop
# Requires a FoundryVTT license and the foundry.zip file to be downloaded manually

# Secret for FoundryVTT username/password (license credentials)
resource "kubernetes_secret" "foundryvtt_credentials" {
  metadata {
    name      = "foundryvtt-credentials"
    namespace = "default"
  }

  data = {
    FOUNDRY_USERNAME = var.foundryvtt_username
    FOUNDRY_PASSWORD = var.foundryvtt_password
  }
}

# Persistent Volume Claim for FoundryVTT data
resource "kubernetes_persistent_volume_claim" "foundryvtt_data" {
  metadata {
    name      = "foundryvtt-data-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"  # Reduced to fit available storage with 3 replicas
      }
    }
    storage_class_name = data.terraform_remote_state.cluster.outputs.longhorn_storage_class
  }
  wait_until_bound = false
}

# Additional PVC for FoundryVTT application config and state
resource "kubernetes_persistent_volume_claim" "foundryvtt_app" {
  metadata {
    name      = "foundryvtt-app-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"  # For application configs, logs, cache
      }
    }
    storage_class_name = data.terraform_remote_state.cluster.outputs.longhorn_storage_class
  }
  wait_until_bound = false
}

# FoundryVTT StatefulSet (better for persistent applications)
resource "kubernetes_manifest" "foundryvtt_statefulset" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "StatefulSet"
    metadata = {
      name      = "foundryvtt"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "foundryvtt"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "foundryvtt"
          }
        }
        spec = {
          # Security context to ensure proper file permissions
          securityContext = {
            fsGroup = 1000
            runAsUser = 1000
            runAsGroup = 1000
          }
          
          containers = [{
            name  = "foundryvtt"
            image = "felddy/foundryvtt:release"
            
            ports = [{
              containerPort = 30000
              name         = "http"
            }]

            env = [
              {
                name = "FOUNDRY_USERNAME"
                valueFrom = {
                  secretKeyRef = {
                    name = "foundryvtt-credentials"
                    key  = "FOUNDRY_USERNAME"
                  }
                }
              },
              {
                name = "FOUNDRY_PASSWORD"
                valueFrom = {
                  secretKeyRef = {
                    name = "foundryvtt-credentials"
                    key  = "FOUNDRY_PASSWORD"
                  }
                }
              },
              {
                name  = "FOUNDRY_RELEASE_URL"
                value = var.foundryvtt_release_url
              },
              {
                name  = "FOUNDRY_MINIFY_STATIC_FILES"
                value = "true"
              },
              {
                name  = "FOUNDRY_PROXY_SSL"
                value = "true"
              },
              {
                name  = "FOUNDRY_PROXY_PORT"
                value = "443"
              },
              {
                name  = "FOUNDRY_ADMIN_KEY"
                value = var.foundryvtt_admin_key
              },
              {
                name  = "CONTAINER_PRESERVE_CONFIG"
                value = "true"
              }
            ]

            volumeMounts = [
              {
                name      = "data"
                mountPath = "/data"
              },
              {
                name      = "app-cache"
                mountPath = "/home/node/.cache"
              },
              {
                name      = "app-cache"
                mountPath = "/home/node/.local"
                subPath   = "local"
              },
              {
                name      = "app-cache"
                mountPath = "/tmp"
                subPath   = "tmp"
              }
            ]

            resources = {
              requests = {
                memory = "1Gi"
                cpu    = "500m"
              }
              limits = {
                memory = "2Gi"
                cpu    = "2"
              }
            }

            livenessProbe = {
              httpGet = {
                path = "/"
                port = 30000
              }
              initialDelaySeconds = 300  # FoundryVTT can take time to start up
              periodSeconds       = 30
              timeoutSeconds      = 10
              failureThreshold    = 3
            }

            readinessProbe = {
              httpGet = {
                path = "/"
                port = 30000
              }
              initialDelaySeconds = 60
              periodSeconds       = 10
              timeoutSeconds      = 5
            }
          }]

          volumes = [
            {
              name = "data"
              persistentVolumeClaim = {
                claimName = "foundryvtt-data-pvc"
              }
            },
            {
              name = "app-cache"
              persistentVolumeClaim = {
                claimName = "foundryvtt-app-pvc"
              }
            }
          ]
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.foundryvtt_credentials,
    kubernetes_persistent_volume_claim.foundryvtt_data,
    kubernetes_persistent_volume_claim.foundryvtt_app
  ]
}

# FoundryVTT Service - ClusterIP since we're using Traefik IngressRoute for Cloudflare Tunnel
resource "kubernetes_service_v1" "foundryvtt_service" {
  metadata {
    namespace = "default"
    name      = "foundryvtt-service"
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "foundryvtt"
    }

    port {
      port        = 30000
      target_port = 30000
      protocol    = "TCP"
    }
  }

  depends_on = [
    kubernetes_manifest.foundryvtt_statefulset
  ]
}

# Let's Encrypt certificate for FoundryVTT
resource "kubernetes_manifest" "foundryvtt_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "foundryvtt-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "foundryvtt-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["foundryvtt.cdklein.com"]
    }
  }
}

# Traefik IngressRoute for FoundryVTT
resource "kubernetes_manifest" "foundryvtt_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
      namespace = "default"
      name      = "foundryvtt-ingressroute"
    }
    
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`foundryvtt.cdklein.com`)"
        services = [{
          kind = "Service"
          name = "foundryvtt-service"
          port = 30000
        }]
      }]
      tls = {
        secretName = "foundryvtt-letsencrypt-tls"
      }
    }
  }

  depends_on = [
    kubernetes_manifest.foundryvtt_statefulset
  ]
}

# DNS record for FoundryVTT - points to Traefik for IngressRoute routing (Cloudflare Tunnel will connect here)
resource "technitium_dns_zone_record" "foundryvtt_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "foundryvtt.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.233"  # Traefik's IP for IngressRoute routing
}

output "foundryvtt_statefulset_name" {
  value = kubernetes_manifest.foundryvtt_statefulset.manifest.metadata.name
}
