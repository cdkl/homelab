resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.18.2" # Use the latest stable version

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Configure cert-manager to use Cloudflare DNS servers for DNS validation
  # This bypasses local DNS issues and queries Cloudflare directly
  set {
    name  = "podDnsPolicy"
    value = "None"
  }
  
  set {
    name  = "podDnsConfig.nameservers[0]"
    value = "1.1.1.1"
  }
  
  set {
    name  = "podDnsConfig.nameservers[1]"
    value = "1.0.0.1"
  }
}

# Cloudflare API token secret
resource "kubernetes_secret" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = "cert-manager"
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  depends_on = [kubernetes_namespace.cert_manager]
}

# Let's Encrypt ClusterIssuer with Cloudflare DNS-01
resource "kubernetes_manifest" "letsencrypt_cloudflare_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-cloudflare"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-cloudflare-private-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token"
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  }
  depends_on = [helm_release.cert_manager, kubernetes_secret.cloudflare_api_token]
}
