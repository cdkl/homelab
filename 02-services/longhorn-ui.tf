resource kubernetes_manifest "longhorn_ui_ingressroute" {
    manifest = {
        apiVersion = "traefik.io/v1alpha1"
        kind      = "IngressRoute"

        metadata = {
            namespace = "longhorn-system"
            name = "longhorn-ui"
        }
        spec = {
            entryPoints = ["web"]
            routes = [{
                kind  = "Rule"
                match = "Host(`longhorn.cdklein.com`)"
                services = [{
                    kind = "Service"
                    name = "longhorn-frontend"
                    port = 80
                }]
            }]
        }
    }
}
