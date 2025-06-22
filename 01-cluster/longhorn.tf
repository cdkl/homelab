resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
  }
}

resource "helm_release" "longhorn" {
  name       = "longhorn"
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.9.0"

  set {
    name  = "defaultSettings.defaultDataPath"
    value = "/var/lib/longhorn"
  }

  set {
    name  = "persistence.defaultClass"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.longhorn_system
  ]
}

# Add output for the storage class
output "longhorn_storage_class" {
  value = "longhorn"
}