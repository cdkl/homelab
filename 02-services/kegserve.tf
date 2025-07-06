resource "kubernetes_secret" "kegserve_rails_master_key" {
  metadata {
    name = "kegserve-rails-master-key"
    namespace = "default"
  }

  data = {
    RAILS_MASTER_KEY = var.rails_master_key
  }
}

# Update the PVC to remove storage_class_name (will use default local-path)
resource "kubernetes_persistent_volume_claim" "kegserve_data" {
  metadata {
    name = "kegserve-data-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = data.terraform_remote_state.cluster.outputs.longhorn_storage_class
  }
  wait_until_bound = false
}

resource "kubernetes_pod" "kegserve" {
    metadata {
        namespace = "default"
        name = "kegserve"
        labels = {
            app = "kegserve"
        }
    }

    spec {
        security_context {
            fs_group = 1000
            run_as_user = 1000
            run_as_group = 1000
        }

        container {
            name  = "kegserve"
            image = "cdklein/kegserve:20250529.1507"

            port {
                container_port = 80
                name          = "http"
            }

            resources {
                requests = {
                    memory = "256Mi"
                    cpu    = "500m"
                }
                limits = {
                    memory = "512Mi"
                    cpu    = "2"
                }
            }

            security_context {
                run_as_user = 1000
                run_as_group = 1000
            }

            volume_mount {
                name       = "data-volume"
                mount_path = "/data"
            }
        

            env_from {
                secret_ref {
                    name = kubernetes_secret.kegserve_rails_master_key.metadata[0].name
                }
            }
        }

        volume {
            name = "data-volume"
            persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim.kegserve_data.metadata[0].name
            }
        }
    }

    depends_on = [
        kubernetes_secret.kegserve_rails_master_key
    ]
}

resource "kubernetes_service_v1" "kegserve_service" {
    metadata {
        namespace = "default"
        name = "kegserve-service"
        annotations = {
            "external-dns.kubernetes.io/hostname" = "kegserve"
            "external-dns.kubernetes.io/without-namespace" = "true"
        }
    }

    spec {
        selector = {
            app = "kegserve" # Ensure this matches the labels of your Pod/Deployment
        }

        port {
            port        = 80       # Port exposed by the Service
            target_port = 80       # Port on the container
            protocol    = "TCP"
        }

#        type = "ClusterIP" # Internal service type
    }

    depends_on = [
        kubernetes_pod.kegserve
    ]
}

# Let's Encrypt certificate for kegserve
resource "kubernetes_manifest" "kegserve_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "kegserve-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "kegserve-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["kegserve.cdklein.com"]
    }
  }
}

resource kubernetes_manifest "kegserve_ingressroute" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind      = "IngressRoute"

        metadata = {
            namespace = "default"
            name = "kegserve-ingressroute"
        }
        spec = {
            entryPoints = ["websecure"]
            routes = [{
                kind  = "Rule"
                match = "Host(`kegserve.cdklein.com`)"
                services =[{
                    kind = "Service"
                    name = "kegserve-service"
                    port = 80
                }]
            }]
            tls = {
                secretName = "kegserve-letsencrypt-tls"
            }
        }
    }

    depends_on = [
        kubernetes_pod.kegserve
    ]
}

resource technitium_dns_zone_record "kegserve_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "kegserve.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = data.terraform_remote_state.cluster.outputs.k3s_master_ip
}

output "kegserve_pod_name" {
    value = kubernetes_pod.kegserve.metadata[0].name
}
