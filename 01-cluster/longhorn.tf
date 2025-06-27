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

  set {
    name  = "defaultBackupStore.backupTarget"
    value = "nfs://lorez.cdklein.com:/volume1/k3s/longhorn"
  }

  depends_on = [
    kubernetes_namespace.longhorn_system
  ]
}

resource "kubernetes_manifest" "longhorn_daily_backup" {
  manifest = {
    "apiVersion" = "longhorn.io/v1beta2"
    "kind"       = "RecurringJob"
    "metadata" = {
      "name"      = "daily-backup"
      "namespace" = kubernetes_namespace.longhorn_system.metadata[0].name
    }
    "spec" = {
      "name"        = "daily-backup"
      "task"        = "backup"
      "cron"        = "03 6 * * *"
      "retain"      = 7
      "concurrency" = 1
      "groups"      = ["default"]
      "labels"      = {
        "backup" = "daily"
      }
    }
  }
  depends_on = [
    helm_release.longhorn
  ]
}

# Add output for the storage class
output "longhorn_storage_class" {
  value = "longhorn"
}

