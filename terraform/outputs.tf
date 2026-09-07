output "k3s_master_ip" {
  description = "k3s control-plane IP"
  value       = var.k3s_master_ip
}

output "k3s_worker_ips" {
  description = "k3s worker IPs"
  value       = var.k3s_worker_ips
}

output "adguard_ip" {
  description = "AdGuard Home admin UI — http://<ip>:3000"
  value       = var.adguard_ip
}

output "k3s_master_vm_id" {
  value = proxmox_virtual_environment_vm.k3s_master.vm_id
}

output "k3s_worker_vm_ids" {
  value = proxmox_virtual_environment_vm.k3s_worker[*].vm_id
}

output "adguard_ct_id" {
  value = proxmox_virtual_environment_container.adguard.vm_id
}

# Copy this block into ansible/inventory/hosts.yml after terraform apply
output "ansible_inventory_hint" {
  description = "Paste this into ansible/inventory/hosts.yml"
  value = <<-EOT
    k3s_master:
      hosts:
        k3s-master-1:
          ansible_host: ${var.k3s_master_ip}
    k3s_workers:
      hosts:
        k3s-worker-1:
          ansible_host: ${var.k3s_worker_ips[0]}
        k3s-worker-2:
          ansible_host: ${var.k3s_worker_ips[1]}
    adguard_hosts:
      hosts:
        adguard:
          ansible_host: ${var.adguard_ip}
  EOT
}

# ── Cloudflare Tunnel ─────────────────────────────────────────────
output "cloudflare_tunnel_id" {
  description = "Tunnel ID — used in cloudflared config"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.id
}

output "cloudflare_tunnel_token" {
  description = "Run: terraform output -raw cloudflare_tunnel_token — paste into ansible/group_vars/k3s_cluster.yml"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homelab.tunnel_token
  sensitive   = true
}
