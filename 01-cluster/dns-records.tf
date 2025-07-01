resource "kubernetes_config_map" "dns_records" {
  metadata {
    name      = "dns-records"
    namespace = kubernetes_namespace.dns.metadata[0].name
  }

  data = {
    "dns-records.json" = jsonencode({
      records = [
        {
          name = "traefik"
          type = "A"
          ttl  = 300
          data = "192.168.101.234"  # Your Traefik LoadBalancer IP
        },
        {
          name = "dns"
          type = "A"
          ttl  = 300
          data = "192.168.101.233"  # Your Technitium LoadBalancer IP
        },
        {
          name = "*.cdklein.com"  # Wildcard record for all subdomains
          type = "A"
          ttl  = 300
          data = "192.168.101.233"  # Routes all subdomains to Traefik
        }
      ],
      soa = {
        mname = "dns.cdklein.com"
        rname = "admin.cdklein.com"
        serial = "1"
        refresh = 3600
        retry = 600
        expire = 604800
        minimum = 300
      }
    })
  }
}