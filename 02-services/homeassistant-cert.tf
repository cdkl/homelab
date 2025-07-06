# Let's Encrypt certificate for Home Assistant
# This certificate is created in Kubernetes but intended for use on the Home Assistant VM
resource "kubernetes_manifest" "homeassistant_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "homeassistant-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "homeassistant-letsencrypt-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["homeassistant.cdklein.com"]
    }
  }
}

# Note: The DNS record for homeassistant.cdklein.com already exists in dns-zone.tf
# pointing to 192.168.101.77 (the Home Assistant VM IP)
