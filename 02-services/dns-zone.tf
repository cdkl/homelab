# This is here because stage 01 creates the Technitium DNS service, and our technitium provider
# assumes that service is already running and available at the specified host.

resource "technitium_dns_zone" "cdklein" {
  name   = "cdklein.com"
  type   = "Primary"
  use_soa_serial_date_scheme = true
  # Optionally, you can set additional zone properties here
}

# dns.cdklein.com DNS directs us specifically to the Technitium DNS server
# This DNS entry needs to exist for stage 01, so it needs to be established in
# the DHCP server's DNS manually if bootstrapping from scratch.
# We specify it here for parallelism with the DHCP server's DNS entry.
resource "technitium_dns_zone_record" "dns_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "dns.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.243"
}

resource "technitium_dns_zone_record" "homeassistant_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "homeassistant.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.77"
}

resource "technitium_dns_zone_record" "hunkerbunker_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "hunkerbunker.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.77"
}

resource "technitium_dns_zone_record" "brewpi_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "brewpi.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.14"
}

resource "technitium_dns_zone_record" "lorez_cdklein" {
  zone       = technitium_dns_zone.cdklein.name
  domain     = "lorez.${technitium_dns_zone.cdklein.name}"
  type       = "A"
  ttl        = 300
  ip_address = "192.168.101.2"
}

resource "technitium_dns_zone_record" "birdnet_cdklein" {
    zone       = technitium_dns_zone.cdklein.name
    domain     = "birdnet.${technitium_dns_zone.cdklein.name}"
    type       = "A"
    ttl        = 300
    ip_address = "192.168.101.172"
}

resource "technitium_dns_zone_record" "bunker1_cdklein" {
    zone       = technitium_dns_zone.cdklein.name
    domain     = "bunker1.${technitium_dns_zone.cdklein.name}"
    type       = "A"
    ttl        = 300
    ip_address = "192.168.101.33"
}

resource "technitium_dns_zone_record" "proxmoxbox_cdklein" {
    zone       = technitium_dns_zone.cdklein.name
    domain     = "proxmoxbox.${technitium_dns_zone.cdklein.name}"
    type       = "CNAME"
    ttl        = 300
    cname     = "bunker1.${technitium_dns_zone.cdklein.name}"
}

