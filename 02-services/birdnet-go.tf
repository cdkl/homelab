resource "kubernetes_pod" "birdnet_go" {
    metadata {
        namespace = "default"
        name = "birdnet-go"
        labels = {
            app = "birdnet-go"
        }
    }

    spec {
        container {
            name  = "birdnet-go"
            image = "ghcr.io/tphakala/birdnet-go:nightly"

            port {
                container_port = 8080
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

            volume_mount {
                name       = "config-volume"
                mount_path = "/config"
            }

            volume_mount {
                name       = "data-volume"
                mount_path = "/data"
            }
        }

        volume {
            name = "config-volume"

            host_path {
                path = "/mnt/pve/nfs/birdnet-go-config"
            }
        }

        volume {
            name = "data-volume"

            host_path {
                path = "/mnt/pve/nfs/birdnet-go-data"
            }
        }
    }

}

resource "kubernetes_service_v1" "birdnet_go_service" {
    metadata {
        namespace = "default"
        name = "birdnet-go-service"
        annotations = {
            "external-dns.kubernetes.io/hostname" = "birdnet-go"
            "external-dns.kubernetes.io/without-namespace" = "true"
        }
    }

    spec {
        selector = {
            app = "birdnet-go" # Ensure this matches the labels of your Pod/Deployment
        }

        port {
            port        = 80       # Port exposed by the Service
            target_port = 8080       # Port on the container
            protocol    = "TCP"
        }

#        type = "ClusterIP" # Internal service type
    }

    depends_on = [
        kubernetes_pod.birdnet_go
    ]
}

# Let's Encrypt certificate for birdnet-go
resource "kubernetes_manifest" "birdnet_go_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "birdnet-go-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "birdnet-go-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["birdnet-go.cdklein.com"]
    }
  }
}

resource "kubernetes_manifest" "birdnet_go_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind      = "IngressRoute"
    metadata = {
      namespace = "default"
      name      = "birdnet-go-ingressroute"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`birdnet-go.cdklein.com`)"
        services =[{
          kind = "Service"
          name = "birdnet-go-service"
          port = 80
        }]
      }]
      tls = {
        secretName = "birdnet-go-letsencrypt-tls"
      }
    }
  }
  depends_on = [
    kubernetes_pod.birdnet_go
  ]
}


output "birdnet_go_pod_name" {
    value = kubernetes_pod.birdnet_go.metadata[0].name
}
