# Cloudflare Tunnel for External Access to FoundryVTT and Authentication Services
#
# This configuration sets up a Cloudflare Tunnel to allow external access to:
# - FoundryVTT (foundryvtt.example.com)
# - TinyAuth (auth.example.com) 
# - PocketID (pocketid.example.com)
# - Static Assets (static.example.com)

# Cloudflare Tunnel Secret
resource "kubernetes_secret" "cloudflare_tunnel" {
  count = var.tunnel_enabled ? 1 : 0
  
  metadata {
    name      = "cloudflare-tunnel"
    namespace = "default"
  }
  
  data = {
    token = var.cloudflare_tunnel_token
  }
}

# Cloudflare Tunnel ConfigMap
resource "kubernetes_config_map" "cloudflare_tunnel_config" {
  count = var.tunnel_enabled ? 1 : 0
  
  metadata {
    name      = "cloudflare-tunnel-config"
    namespace = "default"
  }

  data = {
    "config.yaml" = yamlencode({
      ingress = [
        # FoundryVTT - Main application
        {
          hostname = "foundryvtt.${var.external_domain}"
          service  = "http://foundryvtt-service.default.svc.cluster.local:30000"
        },
        # TinyAuth - Authentication service
        {
          hostname = "auth.${var.external_domain}" 
          service  = "http://tinyauth.default.svc.cluster.local:3000"
        },
        # PocketID - OAuth provider
        {
          hostname = "pocketid.${var.external_domain}"
          service  = "http://pocketid.default.svc.cluster.local:1411"
        },
        # Static Assets - TinyAuth backgrounds
        {
          hostname = "static.${var.external_domain}"
          service  = "http://static-assets.default.svc.cluster.local:80"
        },
        # Default rule - catch all
        {
          service = "http_status:404"
        }
      ]
    })
  }
}

# Cloudflare Tunnel Deployment
resource "kubernetes_manifest" "cloudflare_tunnel_deployment" {
  count = var.tunnel_enabled ? 1 : 0
  
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "cloudflare-tunnel"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "cloudflare-tunnel"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "cloudflare-tunnel"
          }
        }
        spec = {
          containers = [{
            name  = "cloudflared"
            image = "cloudflare/cloudflared:latest"
            
            args = [
              "tunnel",
              "--config",
              "/etc/cloudflared/config.yaml",
              "run",
              "--token-file",
              "/etc/cloudflared/token"
            ]
            
            env = [{
              name  = "TUNNEL_METRICS"
              value = "0.0.0.0:2000"
            }]
            
            ports = [
              {
                containerPort = 2000
                name         = "metrics"
              }
            ]
            
            volumeMounts = [
              {
                name      = "config"
                mountPath = "/etc/cloudflared/config.yaml"
                subPath   = "config.yaml"
                readOnly  = true
              },
              {
                name      = "tunnel-secret"
                mountPath = "/etc/cloudflared/token"
                subPath   = "token"
                readOnly  = true
              }
            ]
            
            livenessProbe = {
              httpGet = {
                path = "/ready"
                port = 2000
              }
              failureThreshold    = 1
              initialDelaySeconds = 10
              periodSeconds       = 10
            }
          }]
          
          volumes = [
            {
              name = "config"
              configMap = {
                name = "cloudflare-tunnel-config"
              }
            },
            {
              name = "tunnel-secret"
              secret = {
                secretName = "cloudflare-tunnel"
              }
            }
          ]
        }
      }
    }
  }
  
  depends_on = [
    kubernetes_secret.cloudflare_tunnel,
    kubernetes_config_map.cloudflare_tunnel_config
  ]
}

# Optional: Service for tunnel metrics (internal monitoring)
resource "kubernetes_service_v1" "cloudflare_tunnel_metrics" {
  count = var.tunnel_enabled ? 1 : 0
  
  metadata {
    name      = "cloudflare-tunnel-metrics"
    namespace = "default"
  }
  
  spec {
    selector = {
      app = "cloudflare-tunnel"
    }
    
    port {
      name        = "metrics"
      port        = 2000
      target_port = 2000
      protocol    = "TCP"
    }
    
    type = "ClusterIP"
  }
}

# Let's Encrypt certificate for tunnel metrics (internal only)
resource "kubernetes_manifest" "tunnel_metrics_letsencrypt_certificate" {
  count = var.tunnel_enabled ? 1 : 0
  
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "tunnel-metrics-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "tunnel-metrics-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["tunnel-metrics.${var.external_domain}"]
    }
  }
}

# TinyAuth-protected IngressRoute for tunnel metrics (internal only)
resource "kubernetes_manifest" "tunnel_metrics_ingressroute" {
  count = var.tunnel_enabled ? 1 : 0
  
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "tunnel-metrics-ingressroute"
      namespace = "default"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`tunnel-metrics.${var.external_domain}`)"
        middlewares = [{
          name = "tinyauth"
        }]
        services = [{
          kind = "Service"
          name = "cloudflare-tunnel-metrics"
          port = 2000
        }]
      }]
      tls = {
        secretName = "tunnel-metrics-letsencrypt-tls"
      }
    }
  }
  
  depends_on = [
    kubernetes_manifest.tunnel_metrics_letsencrypt_certificate,
    kubernetes_manifest.tinyauth_middleware
  ]
}

# DNS record for tunnel metrics (internal only - not exposed via tunnel)
resource "technitium_dns_zone_record" "tunnel_metrics_cdklein" {
  count = var.tunnel_enabled ? 1 : 0
  
  zone       = technitium_dns_zone.cdklein.name
  domain     = "tunnel-metrics.${var.external_domain}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.233"  # Traefik IP for internal access only
}

# Output tunnel information
output "tunnel_services" {
  value = var.tunnel_enabled ? {
    foundryvtt  = "foundryvtt.${var.external_domain}"
    auth        = "auth.${var.external_domain}"
    pocketid    = "pocketid.${var.external_domain}"
    static      = "static.${var.external_domain}"
  } : {}
  description = "External URLs for tunnel services"
}

output "tunnel_metrics_url" {
  value = var.tunnel_enabled ? "https://tunnel-metrics.${var.external_domain}/metrics" : "Tunnel disabled"
  description = "Internal URL for tunnel metrics (TinyAuth protected)"
}
