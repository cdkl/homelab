# CoreDNS configuration with hardcoded Technitium DNS
# Primary: Technitium DNS (192.168.101.243) only
# No fallback to prevent Cloudflare tunnel circular routing

resource "kubernetes_config_map_v1_data" "coredns_fallback" {
  metadata {
    name      = "coredns"
    namespace = "kube-system"
  }

  data = {
    Corefile = <<-EOF
      .:53 {
          errors
          health
          ready
          kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
          }
          hosts /etc/coredns/NodeHosts {
            ttl 60
            reload 15s
            fallthrough
          }
          prometheus :9153
          forward . 192.168.101.100
          cache 30
          loop
          reload
          loadbalance
          import /etc/coredns/custom/*.override
      }
      import /etc/coredns/custom/*.server
    EOF

    NodeHosts = <<-EOF
      192.168.101.185 k3s-master
      192.168.101.186 k3s-worker-1
    EOF
  }

  force = true

  # Ensure this runs after the cluster is up and DNS service exists
}
