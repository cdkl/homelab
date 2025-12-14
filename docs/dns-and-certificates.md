# DNS Configuration and Certificate Management

This document explains the DNS architecture and cert-manager configuration used in this homelab to enable reliable SSL certificate issuance and renewal.

## Problem Statement

The homelab uses a local domain (`cdklein.com`) for internal services while also needing SSL certificates from Let's Encrypt via DNS-01 challenges. This creates a complex DNS resolution scenario where:

1. **Local services** (dns.cdklein.com, traefik.cdklein.com, etc.) need to resolve to internal IPs
2. **Certificate validation** needs to query Cloudflare's authoritative nameservers for the domain
3. **DNS-01 challenges** require cert-manager to verify TXT records in Cloudflare

## DNS Architecture

### Overview
```
┌─────────────────────────────────────────────────────────────┐
│                    Cluster DNS Resolution                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────┐    ┌──────────────────────────────────┐  │
│  │   CoreDNS     │────│     Technitium DNS Server       │  │
│  │  (10.43.0.10) │    │      (192.168.101.243)          │  │
│  └───────────────┘    └──────────────────────────────────┘  │
│                                      │                     │
│                      ┌───────────────┼───────────────────┐ │
│                      │               ▼                   │ │
│                      │   ┌─────────────────────────────┐ │ │
│                      │   │    Local Zone Records      │ │ │
│                      │   │                             │ │ │
│                      │   │  dns.cdklein.com           │ │ │
│                      │   │  → 192.168.101.243         │ │ │
│                      │   │                             │ │ │
│                      │   │  traefik.cdklein.com       │ │ │
│                      │   │  → 192.168.101.233         │ │ │
│                      │   │                             │ │ │
│                      │   │  (all local services...)   │ │ │
│                      │   └─────────────────────────────┘ │ │
│                      │                                   │ │
│                      │   ┌─────────────────────────────┐ │ │
│                      │   │   Conditional Forwarder    │ │ │
│                      │   │                             │ │ │
│                      │   │  cdklein.com domain queries │ │ │
│                      │   │  → piotr.ns.cloudflare.com │ │ │
│                      │   │  → fay.ns.cloudflare.com   │ │ │
│                      │   └─────────────────────────────┘ │ │
│                      └───────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                Cert-Manager DNS Resolution                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐     ┌─────────────────────────────────┐   │
│  │ cert-manager │────▶│      Cloudflare DNS             │   │
│  │   pods       │     │                                 │   │
│  │              │     │  1.1.1.1 (primary)            │   │
│  │ dnsPolicy:   │     │  1.0.0.1 (secondary)          │   │
│  │   None       │     │                                 │   │
│  └──────────────┘     └─────────────────────────────────┘   │
│                                                             │
│  (Bypasses cluster DNS entirely)                            │
└─────────────────────────────────────────────────────────────┘
```

### Components

#### 1. Pi-hole + Unbound DNS VM
- **IP**: 192.168.101.100 (dedicated VM)
- **Role**: LAN DNS with local overrides; upstream recursion by Unbound (DoT)
- **Configuration**:
  - Pi-hole v6 with etc_dnsmasq_d = false; local records come from dns.hosts / dns.cnameRecords
  - Unbound listening on 127.0.0.1:5335, DoT upstreams 1.1.1.1#cloudflare-dns.com and 9.9.9.9#dns.quad9.net
  - TLS CA bundle set (tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt)

#### 2. CoreDNS (Cluster DNS)
- **IP**: 10.43.0.10 (Kubernetes service)
- **Role**: Forwards all DNS queries to Pi-hole
- **Configuration**: Simple forwarding to `192.168.101.100`

#### 3. Cert-Manager DNS Configuration
- **Special DNS Policy**: `dnsPolicy: None`
- **Custom Nameservers**: `1.1.1.1`, `1.0.0.1`
- **Purpose**: Bypass local DNS to query Cloudflare directly

## DNS Resolution Flows

### Local Service Resolution (Normal Pods)
```
Pod → CoreDNS → Pi-hole → (dns.hosts override or Unbound) → Returns IP
```

**Example**: `pihole.cdklein.com` → `192.168.101.100`

### Certificate Validation (Cert-Manager Pods)
```
Cert-Manager → Cloudflare DNS (1.1.1.1) → Returns Authoritative Answer
```

**Example**: 
- `cdklein.com` A record → `172.64.80.1` (from Cloudflare)
- `_acme-challenge.cdklein.com` TXT → Challenge token (from Cloudflare)

### External Domain Resolution (Normal Pods)
```
Pod → CoreDNS → Technitium → Cloudflare DNS → Returns Public IP
```

**Example**: `google.com` → `142.251.41.78`

## Certificate Management Setup

### Cert-Manager Configuration

The cert-manager is configured with special DNS settings to ensure reliable certificate issuance:

```yaml
# In Helm values (via Terraform)
podDnsPolicy: "None"
podDnsConfig:
  nameservers:
    - "1.1.1.1"
    - "1.0.0.1"
```

### ClusterIssuer Configuration

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-cloudflare
spec:
  acme:
    email: your-email@domain.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-cloudflare-private-key
    solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

## DNS-01 Challenge Process

### Step-by-Step Flow

1. **Certificate Request**: Application requests certificate for `service.cdklein.com`

2. **Challenge Creation**: Cert-manager creates ACME challenge with Let's Encrypt

3. **TXT Record Creation**: Cert-manager uses Cloudflare API to create `_acme-challenge.service.cdklein.com` TXT record

4. **DNS Validation**: 
   - Cert-manager queries Cloudflare DNS directly (`1.1.1.1`)
   - Resolves `cdklein.com` to verify domain exists
   - Queries TXT record to verify propagation

5. **Challenge Completion**: Let's Encrypt validates TXT record and issues certificate

6. **Cleanup**: Cert-manager removes TXT record from Cloudflare

### Why This Architecture Works

#### Problem with Standard Setup
- Local DNS zone took precedence over conditional forwarding
- Cert-manager couldn't resolve base domain (`cdklein.com`)
- DNS validation failed with "no such host" errors

#### Solution Benefits
- **Separation of Concerns**: Local services use local DNS, cert validation uses authoritative DNS
- **Reliability**: Cert-manager always queries authoritative nameservers
- **Flexibility**: Local DNS can be modified without affecting certificate issuance
- **Performance**: Direct queries to Cloudflare eliminate DNS forwarding delays

## Configuration Files

### Terraform Configuration

#### DNS Server Setup (`01-cluster/pihole-unbound-vm.tf`)
```hcl
# Technitium DNS configuration with conditional forwarding
```hcl
# Unbound DoT configuration (excerpt written by cloud-init provisioner)
server:
  interface: 127.0.0.1
  port: 5335
  tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt

forward-zone:
  name: "."
  forward-tls-upstream: yes
  forward-addr: 1.1.1.1@853#cloudflare-dns.com
  forward-addr: 9.9.9.9@853#dns.quad9.net
```

```hcl
# CoreDNS forwards to Pi-hole (example values config)
resource "kubernetes_config_map_v1" "coredns" {
  # ...data["Corefile"] includes forward . 192.168.101.100
}
```

```hcl
# Stage 2: Manage local overrides via Pi-hole v6 (02-services/pihole-local-dns.tf)
# Terraform builds arrays and sets via pihole-FTL --config
locals {
  hosts_array = ["192.168.101.100 pihole.cdklein.com", "192.168.101.233 traefik.cdklein.com"]
  cname_array = ["proxmoxbox.cdklein.com bunker1.cdklein.com"]
}
# ... null_resource with remote-exec calls:
#   pihole-FTL --config dns.hosts    '<json hosts_array>'
#   pihole-FTL --config dns.cnameRecords '<json cname_array>'
```

#### Cert-Manager Setup (`01-cluster/cert-manager.tf`)
```hcl
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  
  # Standard configuration
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Custom DNS configuration for cert-manager
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
```

## Troubleshooting

### Common Issues

#### "no such host" errors
- **Symptom**: Cert-manager logs show `dial udp: lookup cdklein.com. on 10.43.0.10:53: no such host`
- **Cause**: Cert-manager using cluster DNS instead of authoritative DNS
- **Solution**: Verify cert-manager pods have `dnsPolicy: None` and custom nameservers

#### DNS propagation failures
- **Symptom**: `DNS record not yet propagated` errors
- **Cause**: Normal delay in DNS propagation
- **Solution**: Wait 1-3 minutes; this is expected behavior

#### Local services not resolving
- **Symptom**: `*.cdklein.com` names fail from LAN or cluster
- **Cause**: Pi-hole v6 not loading dnsmasq.d (etc_dnsmasq_d=false) or dns.hosts list missing
- **Solution**: Inspect with `docker exec pihole pihole-FTL --config dns.hosts`; re-apply 02-services to update hosts/cnames

### Validation Commands

#### Test DNS Resolution from Cluster
```bash
# Test local service resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup pihole.cdklein.com

# Test base domain resolution  
kubectl run dns-test --image=alpine --rm -it --restart=Never -- sh -c "apk add bind-tools && dig cdklein.com"
```

#### Verify Cert-Manager DNS Configuration
```bash
# Check cert-manager pod DNS configuration
kubectl get pod -n cert-manager -l app.kubernetes.io/name=cert-manager -o yaml | grep -A 10 -B 5 "dns"
```

#### Test Certificate Issuance
```bash
# Create test certificate
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-cloudflare
    kind: ClusterIssuer
  dnsNames:
  - test.cdklein.com
EOF

# Monitor progress
kubectl get certificate test-cert
kubectl describe certificate test-cert
```

## Historical Context

### The Original Problem
When `192.168.101.1` (likely the router/gateway) was removed as a DNS forwarder due to traffic concerns, it broke cert-manager's ability to resolve the `cdklein.com` domain. The router was providing proper domain resolution that included both local overrides and upstream DNS forwarding.

### Evolution of the Solution
1. **Initial approach**: Add conditional forwarding in Technitium
2. **First issue**: Local primary zone took precedence over conditional forwarding
3. **Second attempt**: Remove base domain A record to force forwarding
4. **Final solution**: Give cert-manager direct access to Cloudflare DNS

This architecture ensures that:
- Local DNS remains authoritative for internal services
- Certificate validation always uses authoritative DNS sources
- The system is resilient to local DNS configuration changes

## DNS Migration Notes (Technitium → Pi-hole + Unbound)

### Scope
- Replace Technitium-managed local zone with Pi-hole v6 local overrides and Unbound DoT upstreams.
- CoreDNS forwards to Pi-hole (192.168.101.100).
- Authoritative DNS for cdklein.com remains in Cloudflare.

### Prerequisites
- Pi-hole VM reachable at 192.168.101.100.
- Unbound configured with DoT and CA bundle:
  - tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt
  - forward-addr: 1.1.1.1@853#cloudflare-dns.com, 9.9.9.9@853#dns.quad9.net
- CoreDNS ConfigMap updated to forward to 192.168.101.100.

### Execute migration
1. Stage 1: Ensure Pi-hole/Unbound VM is up and Unbound healthy:
   - docker logs unbound
   - docker exec unbound unbound-checkconf /opt/unbound/etc/unbound/unbound.conf
2. Stage 2: Apply local DNS via Terraform:
   - Edit records in 02-services/pihole-local-dns.tf (local.merged_hosts and local.cnames)
   - terraform apply -target=null_resource.pihole_local_dns
   - This sets Pi-hole v6 dns.hosts/dns.cnameRecords via pihole-FTL
3. Update any clients/DHCP to use 192.168.101.100 if not already.

### Verification checklist
- External resolution (through Unbound DoT):
  - nslookup www.google.com 192.168.101.100
- Local overrides (Pi-hole dns.hosts):
  - nslookup pihole.cdklein.com 192.168.101.100 → 192.168.101.100
  - nslookup traefik.cdklein.com 192.168.101.100 → 192.168.101.233
- Cluster path:
  - kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup pihole.cdklein.com
- Cert-manager path remains independent (dnsPolicy: None, nameservers: 1.1.1.1, 1.0.0.1).

### Troubleshooting quick refs
- Inspect Pi-hole v6 local records:
  - docker exec pihole pihole-FTL --config dns.hosts
  - docker exec pihole pihole-FTL --config dns.cnameRecords
- Pi-hole v6 ignores /etc/dnsmasq.d by default (etc_dnsmasq_d=false in pihole.toml).
- Reload DNS:
  - docker exec pihole pihole reloaddns
- Unbound health:
  - docker logs unbound
  - docker exec unbound unbound-checkconf /opt/unbound/etc/unbound/unbound.conf
- If SERVFAILs for externals, verify tls-cert-bundle exists and path is correct.

### Rollback options
- Temporary cluster bypass (keep services up while investigating):
  - Apply CoreDNS fallback to public resolvers (see 01-cluster/coredns-fallback.tf) to forward . to 1.1.1.1, 1.0.0.1.
- Pi-hole emergency passthrough:
  - In Pi-hole, set DNS upstream to 1.1.1.1#53 (plain) or add an additional upstream, then reload.
- Client-side emergency:
  - Point a workstation’s DNS to 1.1.1.1 temporarily to restore internet name resolution.

### Operations notes
- Routine changes to local DNS should go through 02-services/pihole-local-dns.tf.
- Prefer full terraform apply; targeted -target=null_resource.pihole_local_dns is acceptable for quick DNS-only edits.
- Keep Cloudflare authoritative records unchanged unless moving a service externally.

### Fresh bootstrap caveats (Pi-hole VM)
- End-to-end Terraform for the Pi-hole VM has not been fully tested from a clean environment. Expect to troubleshoot first-time provisioning.
- Common first-boot gotchas and fixes:
  1. systemd-resolved still bound to port 53
     - Fix: sudo systemctl disable --now systemd-resolved; rebuild /etc/resolv.conf with public resolvers before starting Unbound/Pi-hole.
  2. Missing CA bundle for Unbound DoT
     - Fix: apt-get install ca-certificates; ensure tls-cert-bundle points to /etc/ssl/certs/ca-certificates.crt.
  3. Docker not present or wrong service name
     - Fix: apt-get install -y docker.io; verify docker service is running.
  4. Pi-hole web password not set (cannot log in)
     - Fix: docker exec pihole pihole -a -p and set a password; or set WEBPASSWORD env on first run.
  5. Local overrides not applied
     - Cause: Pi-hole v6 ignores /etc/dnsmasq.d by default (etc_dnsmasq_d=false)
     - Fix: Apply 02-services to populate dns.hosts/dns.cnameRecords (pihole-FTL --config ...), then pihole reloaddns.
  6. External lookups SERVFAIL
     - Fix: verify Unbound config syntax (docker exec unbound unbound-checkconf ...), logs, and network reachability to 1.1.1.1:853/9.9.9.9:853.
- Quick smoke test after bootstrap:
  - nslookup www.google.com 192.168.101.100 (external)
  - nslookup pihole.cdklein.com 192.168.101.100 (local)
  - From a cluster pod: nslookup pihole.cdklein.com
- Routine changes to local DNS should go through 02-services/pihole-local-dns.tf.
- Prefer full terraform apply; targeted -target=null_resource.pihole_local_dns is acceptable for quick DNS-only edits.
- Keep Cloudflare authoritative records unchanged unless moving a service externally.
