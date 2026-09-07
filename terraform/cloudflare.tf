# ==============================================================
# Cloudflare Tunnel for prateeksavanur.dev
# Provides public HTTPS access to the portfolio website
# with no port forwarding — cloudflared dials out from inside k3s
# ==============================================================

# Random 32-byte secret for this tunnel
resource "random_bytes" "tunnel_secret" {
  length = 32
}

# Create the named Cloudflare Tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared" "homelab" {
  account_id = var.cloudflare_account_id
  name       = "homelab"
  secret     = random_bytes.tunnel_secret.base64
}

# Configure hostname → service routing inside the tunnel
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homelab.id

  config {
    # Apex domain → Traefik ingress controller inside k3s
    ingress_rule {
      hostname = "prateeksavanur.dev"
      service  = "http://traefik.traefik.svc.cluster.local:80"
    }

    # www subdomain → same Traefik
    ingress_rule {
      hostname = "www.prateeksavanur.dev"
      service  = "http://traefik.traefik.svc.cluster.local:80"
    }

    # Catch-all required by cloudflared
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Look up the Cloudflare zone for the domain
data "cloudflare_zone" "domain" {
  name = "prateeksavanur.dev"
}

# CNAME: prateeksavanur.dev → tunnel
resource "cloudflare_record" "apex" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "@"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

# CNAME: www.prateeksavanur.dev → tunnel
resource "cloudflare_record" "www" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "www"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.homelab.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}
