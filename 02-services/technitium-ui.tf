# Let's Encrypt certificate for technitium DNS UI
resource "kubernetes_manifest" "technitium_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "technitium-letsencrypt-cert"
      namespace = "dns"
    }
    spec = {
      secretName = "technitium-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["technitium.cdklein.com"]
    }
  }
}

resource "kubernetes_manifest" "technitium_ui_ingress" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"

    metadata = {
      namespace = "dns"
      name      = "technitium-ui"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        kind  = "Rule"
        match = "Host(`technitium.cdklein.com`)"
        services = [{
          kind = "Service"
          name = "technitium"
          port = 80
        }]
      }]
      tls = {
        secretName = "technitium-letsencrypt-tls"
      }
    }
  }
}

resource "technitium_dns_zone_record" "technitium_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "technitium.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = data.terraform_remote_state.cluster.outputs.k3s_master_ip
}
