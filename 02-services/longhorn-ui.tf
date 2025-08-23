# Let's Encrypt certificate for longhorn
resource "kubernetes_manifest" "longhorn_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "longhorn-letsencrypt-cert"
      namespace = "longhorn-system"
    }
    spec = {
      secretName = "longhorn-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["longhorn.cdklein.com"]
    }
  }
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
            entryPoints = ["websecure"]
            routes = [{
                kind  = "Rule"
                match = "Host(`longhorn.cdklein.com`)"
                middlewares = [{
                    name = "tinyauth"
                }]
                services = [{
                    kind = "Service"
                    name = "longhorn-frontend"
                    port = 80
                }]
            }]
            tls = {
                secretName = "longhorn-letsencrypt-tls"
            }
        }
    }
}

# TinyAuth middleware for longhorn-system namespace
resource "kubernetes_manifest" "tinyauth_middleware_longhorn" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "tinyauth"
      namespace = "longhorn-system"
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

resource "technitium_dns_zone_record" "longhorn_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "longhorn.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.233"  # Traefik IP for IngressRoute routing
}
