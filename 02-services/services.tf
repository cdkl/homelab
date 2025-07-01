provider "kubernetes" {
  config_path    = "~/.kube/config"
}

resource "kubernetes_manifest" "traefik_dashboard_config" {
    manifest = {
        apiVersion = "helm.cattle.io/v1"
        kind       = "HelmChartConfig"
        metadata = {
            name      = "traefik"
            namespace = "kube-system"
        }
        spec = {
            valuesContent = <<EOT
ingressRoute:
  dashboard:
    enabled: true
EOT
        }
    }
}

resource "kubernetes_manifest" "traefik_dashboard_service" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind       = "IngressRoute"
        metadata = {
            name      = "traefik-dashboard"
            namespace = "kube-system"
        }
        spec = {
            entryPoints = ["web"]
            routes = [{
                kind  = "Rule"
                match = "Host(`traefik.cdklein.com`)"
                # match = "Host(`traefik.cdklein.com`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))"
                services = [{
                    kind = "TraefikService"
                    name = "api@internal"
                }]
            }]
        }
    }

    depends_on = [ kubernetes_manifest.traefik_dashboard_config ]
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

resource kubernetes_manifest "birdnet_go_ingressroute" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind      = "IngressRoute"

        metadata = {
            namespace = "default"
            name = "birdnet-go-ingressroute"
        }
        spec = {
            entryPoints = ["web"]
            routes = [{

                kind  = "Rule"
                match = "Host(`birdnet-go.cdklein.com`)"
                services =[{
                    kind = "Service"
                    name = "birdnet-go-service"
                    port = 80
                }]
            }]
        }
    }

    depends_on = [
        kubernetes_pod.birdnet_go
    ]
}

# resource "kubernetes_manifest" "traefik-dashboard-config" {
#     manifest = yamldecode(file("${path.module}/kubernetes/traefik-dashboard-config.yaml"))

#     depends_on = [
#         proxmox_vm_qemu.k3s-master,
#         proxmox_vm_qemu.k3s-worker
#     ]
# }

# resource "kubernetes_manifest" "traefik_dashboard_service" {
#   manifest = yamldecode(file("${path.module}/kubernetes/traefik-dashboard-service.yaml"))

#   depends_on = [
#     proxmox_vm_qemu.k3s-master,
#     proxmox_vm_qemu.k3s-worker
#   ]
# }

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

output "birdnet_go_pod_name" {
    value = kubernetes_pod.birdnet_go.metadata[0].name
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

resource kubernetes_manifest "kegserve_ingressroute" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind      = "IngressRoute"

        metadata = {
            namespace = "default"
            name = "kegserve-ingressroute"
        }
        spec = {
            entryPoints = ["web"]
            routes = [{

                kind  = "Rule"
                match = "Host(`kegserve.cdklein.com`)"
                services =[{
                    kind = "Service"
                    name = "kegserve-service"
                    port = 80
                }]
            }]
        }
    }

    depends_on = [
        kubernetes_pod.birdnet_go
    ]
}

output "kegserve_pod_name" {
    value = kubernetes_pod.kegserve.metadata[0].name
}

resource "kubernetes_secret" "kegserve_rails_master_key" {
  metadata {
    name = "kegserve-rails-master-key"
    namespace = "default"
  }

  data = {
    RAILS_MASTER_KEY = var.rails_master_key
  }
}

# Remove the PV resource entirely since local-path will handle storage

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

resource kubernetes_manifest "longhorn_ui_ingressroute" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind      = "IngressRoute"

        metadata = {
            namespace = "longhorn-system"
            name = "longhorn-ui"
        }
        spec = {
            entryPoints = ["web"]
            routes = [{
                kind  = "Rule"
                match = "Host(`longhorn.cdklein.com`)"
                services = [{
                    kind = "Service"
                    name = "longhorn-frontend"
                    port = 80
                }]
            }]
        }
    }
}

