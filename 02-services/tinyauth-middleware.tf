resource "kubernetes_manifest" "tinyauth_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "tinyauth"
      namespace = "default"
    }
    spec = {
      forwardAuth = {
        address = "http://tinyauth.default.svc.cluster.local:3000/api/auth/traefik"
        authResponseHeaders = [
          "X-Forwarded-User"
        ]
      }
    }
  }
}
