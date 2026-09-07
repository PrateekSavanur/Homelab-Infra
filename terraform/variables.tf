# ==============================================================
# Proxmox Connection
# ==============================================================

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g., https://192.168.1.10:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token — format: 'user@pam!tokenid=uuid-secret'"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (true for self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user on the Proxmox host (used by the provider for file uploads)"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name (shown in the web UI, usually 'pve')"
  type        = string
  default     = "pve"
}

# ==============================================================
# Storage Pools
# ==============================================================

variable "storage_ssd" {
  description = "Proxmox storage ID backed by the 1 TB SSD (OS disks, k3s PVCs)"
  type        = string
  default     = "local-lvm"
}

variable "storage_hdd" {
  description = "Proxmox storage ID backed by the 4 TB HDD (media passthrough to worker-2)"
  type        = string
  default     = "hdd-storage"
}

# ==============================================================
# Networking
# ==============================================================

variable "network_bridge" {
  description = "Proxmox Linux bridge name"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "LAN gateway IP"
  type        = string
  default     = "192.168.68.1"
}

variable "dns_server" {
  description = "Upstream DNS for cloud-init (will be overridden by AdGuard after setup)"
  type        = string
  default     = "1.1.1.1"
}

variable "subnet_prefix" {
  description = "Subnet prefix length"
  type        = number
  default     = 24
}

# ==============================================================
# Static IP Assignments
# ==============================================================

variable "k3s_master_ip" {
  description = "Static IP for the k3s control-plane node"
  type        = string
  default     = "192.168.68.110"
}

variable "k3s_worker_ips" {
  description = "Static IPs for k3s worker nodes (index 0 = worker-1, index 1 = worker-2/media)"
  type        = list(string)
  default     = ["192.168.68.111", "192.168.68.112"]
}

variable "adguard_ip" {
  description = "Static IP for the AdGuard Home LXC container"
  type        = string
  default     = "192.168.68.50"
}

# ==============================================================
# VM / Container Config
# ==============================================================

variable "vm_user" {
  description = "Default non-root user created inside VMs via cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key injected into VMs and LXC containers"
  type        = string
}

variable "master_vm_id" {
  description = "Proxmox VM ID for k3s master"
  type        = number
  default     = 100
}

variable "worker_vm_id_start" {
  description = "Starting Proxmox VM ID for workers (workers get IDs 101, 102, …)"
  type        = number
  default     = 101
}

variable "adguard_ct_id" {
  description = "Proxmox container ID for AdGuard"
  type        = number
  default     = 200
}

variable "media_disk_size_gb" {
  description = "Size (GB) of the HDD-backed data disk attached to worker-2 for Jellyfin media"
  type        = number
  default     = 2000
}

# ==============================================================
# Cloudflare
# ==============================================================

variable "cloudflare_api_token" {
  description = "Cloudflare API token — needs Zone:Read, Zone:Edit, Cloudflare Tunnel:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID — shown in the right sidebar of your Cloudflare dashboard"
  type        = string
}


# ==============================================================
# VM Template
# ==============================================================

variable "vm_template_id" {
  description = "Promox VM Id of ubuntu 22.04 cloud-init template (create manually)"
  type = number
  default = 9000
}