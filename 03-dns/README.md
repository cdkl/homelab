# Technitium DNS cluster

Live source of truth is the Technitium UI on **ns1**. The cluster copies zones, records, blocklists, and settings to ns2. Git is not the live config.

| Role | VM | Proxmox | IP |
|---|---|---|---|
| Primary | ns1 | bunker1 | 192.168.101.239 |
| Secondary | ns2 | bunker2 (`192.168.101.3`) | 192.168.101.240 |

- Admin: http://192.168.101.239:5380/ (or `:240`). Password is in `.secrets`.
- Cluster domain: `cluster.home.arpa` (private; not a LAN name you query).
- Local zone: `cdklein.com` (catalog member; unknown names stay NXDOMAIN).
- LAN clients should use `.239` and `.240` once DHCP is cut over. Pi-hole at `.100` is leftover until that happens.

## Day to day: add or change a name

1. Open ns1: http://192.168.101.239:5380/
2. Zones → `cdklein.com`.
3. Add or edit an **A** or **CNAME**. Use the FQDN (`newsvc.cdklein.com`).
4. Do not add HTTPS/SVCB records for `cdklein.com` (Chrome ECH).
5. Check both nodes:

```bash
nslookup newsvc.cdklein.com 192.168.101.239
nslookup newsvc.cdklein.com 192.168.101.240
```

Writes belong on the primary. If ns1 is down you can still *query* ns2; promote ns2 in Administration → Cluster only if ns1 is gone for good.

Do **not** run `scripts/configure.py` or `terraform apply` to add a hostname. `configure.py` is rebuild-only and overwrites. Terraform manages the VMs and is set to ignore drift / prevent destroy.

## What `records.yaml` is

A seed from the first import, not the live zone. Updating it when you add a name is optional (human inventory only). Nothing applies it automatically.

If you rebuild the cluster from scratch, edit `records.yaml` to match what you want, then run `configure.py`.

## Rebuild (rare)

```bash
export PASS="$(grep TECHNITIUM_ADMIN_PASSWORD .secrets | cut -d= -f2)"
scripts/bootstrap.sh 192.168.101.239 ns1.cluster.home.arpa "$PASS"
scripts/bootstrap.sh 192.168.101.240 ns2.cluster.home.arpa "$PASS"
python3 scripts/configure.py --password "$PASS"
```

ns2 cannot be cloned onto bunker2 from bunker1 (`local-lvm`). Clone VM 108 on bunker1, then `qm migrate 108 bunker2`.

## Cutover (still pending)

1. DHCP DNS servers: `192.168.101.239`, `192.168.101.240` (drop `.100`).
2. Confirm LAN clients resolve via the new pair.
3. Stop the Pi-hole VM. Do not apply `02-services` `pihole-local-dns` afterward.

## Backup

Proxmox backup of ns1 is enough for disaster recovery; ns2 is the live replica. A Technitium Settings → Backup zip is optional extra, not something to treat as source of truth.
