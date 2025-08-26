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

#### 1. Technitium DNS Server
- **IP**: 192.168.101.243 (MetalLB LoadBalancer)
- **Role**: Authoritative DNS server for local `cdklein.com` zone
- **Configuration**:
  - **Primary zone**: `cdklein.com` with local service records
  - **Conditional forwarder**: Routes `cdklein.com` domain queries to Cloudflare nameservers
  - **General forwarders**: `1.1.1.1`, `1.0.0.1` for all other domains

#### 2. CoreDNS (Cluster DNS)
- **IP**: 10.43.0.10 (Kubernetes service)
- **Role**: Forwards all DNS queries to Technitium DNS server
- **Configuration**: Simple forwarding to `192.168.101.243`

#### 3. Cert-Manager DNS Configuration
- **Special DNS Policy**: `dnsPolicy: None`
- **Custom Nameservers**: `1.1.1.1`, `1.0.0.1`
- **Purpose**: Bypass local DNS to query Cloudflare directly

## DNS Resolution Flows

### Local Service Resolution (Normal Pods)
```
Pod → CoreDNS → Technitium → Local Zone → Returns Local IP
```

**Example**: `dns.cdklein.com` → `192.168.101.243`

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

#### DNS Server Setup (`01-cluster/dns.tf`)
```hcl
# Technitium DNS configuration with conditional forwarding
resource "kubernetes_config_map" "technitium_init" {
  # ... 
  data = {
    "init-config.json" = jsonencode({
      forwarders = [
        {
          address = "1.1.1.1"
          port    = 53
          type    = "Udp"
        },
        {
          address = "1.0.0.1"
          port    = 53
          type    = "Udp"
        }
      ]
      conditionalForwarders = [
        {
          zone = "cdklein.com"
          forwarders = [
            {
              address = "piotr.ns.cloudflare.com"
              port    = 53
              type    = "Udp"
            },
            {
              address = "fay.ns.cloudflare.com"
              port    = 53
              type    = "Udp"
            }
          ]
        }
      ]
      zones = [
        {
          name = "cdklein.com"
          type = "Primary"
        }
      ]
      # ...
    })
  }
}
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
- **Symptom**: Cannot reach `dns.cdklein.com`, `traefik.cdklein.com`, etc.
- **Cause**: Missing local DNS records
- **Solution**: Verify Technitium DNS has all required A records

### Validation Commands

#### Test DNS Resolution from Cluster
```bash
# Test local service resolution
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup dns.cdklein.com

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
