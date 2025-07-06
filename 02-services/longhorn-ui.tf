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

resource "technitium_dns_zone_record" "longhorn_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "longhorn.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = data.terraform_remote_state.cluster.outputs.k3s_master_ip
}
