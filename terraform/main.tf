# ==============================================================
# k3s Master Node
# 4 vCPU | 8 GB RAM | 50 GB SSD
# Cloned from VM template 9000 (ubuntu-2204-template)
# ==============================================================

resource "proxmox_virtual_environment_vm" "k3s_master" {
  name        = "k3s-master-1"
  description = "k3s Control Plane"
  node_name   = var.proxmox_node
  vm_id       = var.master_vm_id
  tags        = ["k3s", "master", "homelab"]
  on_boot     = true

  clone {
    vm_id   = var.vm_template_id   # 9000
    full    = true
    retries = 3
  }

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 8192
  }

  # Resize the cloned root disk to 50 GB
  disk {
    datastore_id = var.storage_ssd
    interface    = "scsi0"
    size         = 50
    discard      = "on"
    iothread     = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.k3s_master_ip}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key)]
    }

    dns {
      servers = [var.dns_server]
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  startup {
    order      = 1
    up_delay   = 30
    down_delay = 15
  }
}

# ==============================================================
# k3s Worker Nodes (count = 2)
# worker-1: 4 vCPU | 16 GB | 50 GB SSD
# worker-2: 4 vCPU | 20 GB | 50 GB SSD + HDD for Jellyfin
# ==============================================================

resource "proxmox_virtual_environment_vm" "k3s_worker" {
  count       = 2
  name        = "k3s-worker-${count.index + 1}"
  description = "k3s Worker ${count.index + 1}${count.index == 1 ? " (media node)" : ""}"
  node_name   = var.proxmox_node
  vm_id       = var.worker_vm_id_start + count.index
  tags        = concat(["k3s", "worker", "homelab"], count.index == 1 ? ["media"] : [])
  on_boot     = true

  clone {
    vm_id   = var.vm_template_id
    full    = true
    retries = 3
  }

  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores   = 4
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = count.index == 1 ? 20480 : 16384
  }

  # Root disk
  disk {
    datastore_id = var.storage_ssd
    interface    = "scsi0"
    size         = 50
    discard      = "on"
    iothread     = true
  }

  # HDD data disk — worker-2 only (Jellyfin media)
  dynamic "disk" {
    for_each = count.index == 1 ? [1] : []

    content {
      datastore_id = var.storage_hdd
      interface    = "scsi1"
      size         = var.media_disk_size_gb
      iothread     = true
    }
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.k3s_worker_ips[count.index]}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key)]
    }

    dns {
      servers = [var.dns_server]
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  startup {
    order      = 2
    up_delay   = 15
    down_delay = 10
  }
}

# ==============================================================
# AdGuard Home LXC Container
# 2 vCPU | 1 GB RAM | 8 GB SSD
# ==============================================================

resource "proxmox_virtual_environment_container" "adguard" {
  description   = "AdGuard Home — network-wide DNS ad-blocking"
  node_name     = var.proxmox_node
  vm_id         = var.adguard_ct_id
  tags          = ["adguard", "dns", "homelab"]
  unprivileged  = true
  start_on_boot = true

  initialization {
    hostname = "adguard"

    ip_config {
      ipv4 {
        address = "${var.adguard_ip}/${var.subnet_prefix}"
        gateway = var.gateway
      }
    }

    user_account {
      keys = [trimspace(var.ssh_public_key)]
    }

    dns {
      servers = [var.dns_server]
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 1024
    swap      = 0
  }

  disk {
    datastore_id = var.storage_ssd
    size         = 8
  }

  network_interface {
    name     = "eth0"
    bridge   = var.network_bridge
    firewall = false
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type             = "debian"
  }

  startup {
    order      = 1
    up_delay   = 5
    down_delay = 5
  }
}