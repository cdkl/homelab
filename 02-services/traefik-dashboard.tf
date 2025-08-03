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

# Let's Encrypt certificate for traefik dashboard
resource "kubernetes_manifest" "traefik_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-letsencrypt-cert"
      namespace = "kube-system"
    }
    spec = {
      secretName = "traefik-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["traefik.cdklein.com"]
    }
  }
}

# TinyAuth middleware for kube-system namespace
resource "kubernetes_manifest" "tinyauth_middleware_traefik" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "tinyauth"
      namespace = "kube-system"
    }
    spec = {
      forwardAuth = {
        address = "http://tinyauth.default.svc.cluster.local:3000/api/auth/traefik"
        authResponseHeaders = [
          "X-Forwarded-User"
        ]
        trustForwardHeader = true
      }
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
            entryPoints = ["websecure"]
            routes = [{
                kind  = "Rule"
                match = "Host(`traefik.cdklein.com`)"
                middlewares = [{
                    name = "tinyauth"
                }]
                services = [{
                    kind = "TraefikService"
                    name = "api@internal"
                }]
            }]
            tls = {
                secretName = "traefik-letsencrypt-tls"
            }
        }
    }

    depends_on = [ kubernetes_manifest.traefik_dashboard_config, kubernetes_manifest.tinyauth_middleware_traefik ]
}

resource "technitium_dns_zone_record" "traefik_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "traefik.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.234"
}
