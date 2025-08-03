resource "kubernetes_persistent_volume_claim" "static_assets_pvc" {
  metadata {
    name      = "static-assets-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "longhorn"
  }
}

resource "kubernetes_manifest" "static_assets_deployment" {
  manifest = {
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "static-assets"
      namespace = "default"
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          app = "static-assets"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "static-assets"
          }
        }
        spec = {
          containers = [{
            name  = "nginx"
            image = "nginx:alpine"
            ports = [{
              containerPort = 80
            }]
            volumeMounts = [{
              name      = "static-files"
              mountPath = "/usr/share/nginx/html"
            }, {
              name      = "nginx-config"
              mountPath = "/etc/nginx/conf.d"
            }]
          }]
          volumes = [
            {
              name = "static-files"
              persistentVolumeClaim = {
                claimName = "static-assets-pvc"
              }
            },
            {
              name = "nginx-config"
              configMap = {
                name = "nginx-static-config"
              }
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_config_map" "nginx_static_config" {
  metadata {
    name      = "nginx-static-config"
    namespace = "default"
  }

  data = {
    "default.conf" = <<EOF
server {
    listen 80;
    server_name localhost;
    
    location / {
        root /usr/share/nginx/html;
        index index.html;
        
        # Enable CORS for cross-origin requests
        add_header Access-Control-Allow-Origin "*";
        add_header Access-Control-Allow-Methods "GET, OPTIONS";
        add_header Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept";
        
        # Cache static assets
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
  }
}

resource "kubernetes_manifest" "static_assets_service" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "static-assets"
      namespace = "default"
    }
    spec = {
      selector = {
        app = "static-assets"
      }
      ports = [{
        port       = 80
        targetPort = 80
        protocol   = "TCP"
      }]
      type = "ClusterIP"
    }
  }
}

# Let's Encrypt certificate for static assets
resource "kubernetes_manifest" "static_assets_letsencrypt_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "static-assets-letsencrypt-cert"
      namespace = "default"
    }
    spec = {
      secretName = "static-assets-tls"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      dnsNames = ["static.cdklein.com"]
    }
  }
}

resource "kubernetes_manifest" "static_assets_ingressroute" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "static-assets-ingressroute"
      namespace = "default"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`static.cdklein.com`)"
        kind  = "Rule"
        services = [{
          name = "static-assets"
          port = 80
        }]
      }]
      tls = {
        secretName = "static-assets-tls"
      }
    }
  }
}

resource "technitium_dns_zone_record" "static_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "static.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.234"
}
