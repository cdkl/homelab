resource "kubernetes_namespace" "dns" {
  metadata {
    name = "dns"
  }
}

resource "kubernetes_config_map" "technitium_init" {
  metadata {
    name      = "technitium-init"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  data = {
    "init-config.json" = jsonencode({
      forwarders = [
        {
          address = "1.1.1.1",
          port    = 53,
          type    = "Udp"
        },
        {
          address = "1.0.0.1",
          port    = 53,
          type    = "Udp"
        }
      ],
      conditionalForwarders = [
        {
          zone = "cdklein.com",
          forwarders = [
            {
              address = "piotr.ns.cloudflare.com",
              port    = 53,
              type    = "Udp"
            },
            {
              address = "fay.ns.cloudflare.com",
              port    = 53,
              type    = "Udp"
            }
          ]
        }
      ],
      zones = [
        {
          name = "cdklein.com",
          type = "Primary"
        }
      ],
      blockLists = [],
      recursion = {
        enabled = true,
        allowedNetworks = ["192.168.0.0/16"]
      }
    })
  }
}

resource "kubernetes_persistent_volume_claim" "technitium_config" {
  metadata {
    name      = "technitium-config"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "longhorn"  # Use Longhorn storage class
  }
  wait_until_bound = false
}

resource "kubernetes_deployment" "technitium" {
  metadata {
    name      = "technitium"
    namespace = kubernetes_namespace.dns.metadata[0].name
    labels = {
      app = "technitium"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "technitium"
      }
    }

    template {
      metadata {
        labels = {
          app = "technitium"
        }
      }

      spec {
        container {
          image = "technitium/dns-server:latest"
          name  = "technitium"

          env {
            name  = "DNS_SERVER_DOMAIN"
            value = "cdklein.com"
          }

          env {
            name  = "DNS_SERVER_ADMIN_PASSWORD"
            value = var.technitium_admin_password
          }

          port {
            container_port = 5380
            name          = "web"
          }

          port {
            container_port = 53
            name          = "dns-tcp"
            protocol      = "TCP"
          }

          port {
            container_port = 53
            name          = "dns-udp"
            protocol      = "UDP"
          }

          resources {
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/dns"
          }

          volume_mount {
            name       = "init-config"
            mount_path = "/app/config/init"
          }

          readiness_probe {
            tcp_socket {
              port = 53
            }
            initial_delay_seconds = 10
            period_seconds       = 10
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.technitium_config.metadata[0].name
          }
        }

        volume {
          name = "init-config"
          config_map {
            name = kubernetes_config_map.technitium_init.metadata[0].name
          }
        }
      }
    }
  }
}

# Add a LoadBalancer service to ensure stable IP
resource "kubernetes_service" "technitium" {
  metadata {
    name      = "technitium"
    namespace = kubernetes_namespace.dns.metadata[0].name
    annotations = {
      "metallb.universe.tf/loadBalancerIPs" = "192.168.101.243"  # First IP in our safe range
    }
  }

  spec {
    type = "LoadBalancer"
    selector = {
      app = "technitium"
    }

    port {
      port        = 53
      target_port = 53
      protocol    = "UDP"
      name        = "dns-udp"
    }

    port {
      port        = 53
      target_port = 53
      protocol    = "TCP"
      name        = "dns-tcp"
    }

    port {
      port        = 80
      target_port = 5380
      name        = "web"
    }
  }
}

resource "kubernetes_manifest" "technitium_ui_ingress_dns" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
      namespace = "dns"
      name      = "technitium-ui-dns"
    }
    spec = {
      entryPoints = ["web"]
      routes = [{
        kind  = "Rule"
        match = "Host(`dns.cdklein.com`)"
        services = [{
          kind = "Service"
          name = "technitium"
          port = 80
        }]
      }]
    }
  }
}


output "technitium_admin_password" {
  value = var.technitium_admin_password
  sensitive = true
}
