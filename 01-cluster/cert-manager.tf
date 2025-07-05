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
}

resource "kubernetes_manifest" "letsencrypt_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-http"
    }
    spec = {
      acme = {
        email  = "seadecline@gmail.com" # <-- Replace with your email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-http-private-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "traefik"
              }
            }
          }
        ]
      }
    }
  }
  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "internal_root_ca" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "internal-root-ca"
    }
    spec = {
      selfSigned = {}
    }
  }
}

resource "kubernetes_manifest" "internal_ca_cert" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "internal-ca"
      namespace = "cert-manager"
    }
    spec = {
      isCA       = true
      commonName = "internal-ca"
      secretName = "internal-ca-key-pair"
      issuerRef = {
        name = "internal-root-ca"
        kind = "ClusterIssuer"
      }
    }
  }
  depends_on = [kubernetes_manifest.internal_root_ca]
}

resource "kubernetes_manifest" "internal_ca_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name      = "internal-ca"
    }
    spec = {
      ca = {
        secretName = "internal-ca-key-pair"
      }
    }
  }
  depends_on = [kubernetes_manifest.internal_ca_cert]
}
