resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  namespace  = "metallb-system"
  create_namespace = true

  # Ensure CRDs are installed
  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "speaker.frr.enabled"
    value = "true"
  }
}

# Configure the IP address pool
# note: terraform plan did not accept kind IPAddressPool, until after I installed the helm release above
# No solution to this right now.
resource "kubernetes_manifest" "metallb_ip_pool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "network-services-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [
        "192.168.101.233-192.168.101.243"  # Safe range after DHCP assignments
      ]
    }
  }

  depends_on = [helm_release.metallb]
}

# Configure L2 advertisement
resource "kubernetes_manifest" "metallb_l2_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "l2-advert"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["network-services-pool"]
    }
  }

  depends_on = [kubernetes_manifest.metallb_ip_pool]
}