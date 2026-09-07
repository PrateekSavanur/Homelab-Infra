# Homelab — Proxmox + k3s + AdGuard

Infrastructure-as-code for a Proxmox homelab using **Terraform** (provisioning) and **Ansible** (configuration).

## Architecture

```
Proxmox Host (64 GB RAM | 1 TB SSD | 4 TB HDD)
│
├── [VM 100] k3s-master-1  — 192.168.68.110   4 vCPU | 8 GB  | 50 GB SSD
├── [VM 101] k3s-worker-1  — 192.168.68.111   4 vCPU | 16 GB | 50 GB SSD
├── [VM 102] k3s-worker-2  — 192.168.68.112   4 vCPU | 20 GB | 50 GB SSD + 2 TB HDD  ← Jellyfin media
└── [CT 200] adguard        — 192.168.68.50    2 vCPU | 1 GB  | 8 GB SSD

k3s cluster services (MetalLB range 192.168.68.200–220)
├── Traefik      — ingress controller (LoadBalancer)
├── cert-manager — TLS certificates
├── Jellyfin     — media server  (http://jellyfin.homelab.local)
└── Website      — nginx site    (http://www.homelab.local)

AdGuard Home    — DNS + ad-blocking  (http://192.168.1.50:3000)
```

---

## Prerequisites

### On your Proxmox host

1. **API Token** — Datacenter → Permissions → API Tokens → Add
   - User: `root@pam` (or a dedicated user with PVEVMAdmin + PVESDNAdmin + Datastore.Allocate)
   - Privilege Separation: **unchecked**
   - Copy the secret — you cannot see it again

2. **Storage pools**
   ```
   # SSD pool (local-lvm already exists by default)
   # HDD pool — add in Datacenter → Storage → Add → Directory
   #   ID: hdd-storage
   #   Directory: /mnt/hdd   (mount your 4 TB disk here first)
   #   Content: Disk image, Container
   ```

3. **SSH key** for the Proxmox root user (needed by the bpg provider for file uploads):
   ```bash
   ssh-copy-id root@<proxmox-ip>
   ```

### On your workstation

```bash
# Terraform >= 1.5
brew install terraform   # macOS
# or: https://developer.hashicorp.com/terraform/install

# Ansible >= 2.15
pip install ansible

# Required Ansible collections
ansible-galaxy collection install \
  community.general \
  ansible.posix \
  community.crypto
```

---

## Usage

### Step 1 — Terraform (create VMs and LXC)

```bash
cd terraform

# Copy and fill in your values
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

# Init, plan, apply
terraform init
terraform plan
terraform apply
```

> After apply, Terraform prints an `ansible_inventory_hint` output.
> The IPs are already set in `ansible/inventory/hosts.yml` — no changes needed unless you customised them.

### Step 2 — Wait for cloud-init to finish

VMs take ~60 seconds to complete cloud-init after Proxmox reports them as started.

```bash
# Verify SSH access to all nodes
ansible all -m ping
```

### Step 3 — Ansible (configure everything)

```bash
cd ansible

# Full stack setup
ansible-playbook playbooks/site.yml

# Or run individual steps
ansible-playbook playbooks/01-common.yml    # baseline OS config
ansible-playbook playbooks/02-k3s.yml       # k3s cluster
ansible-playbook playbooks/03-adguard.yml   # AdGuard Home
ansible-playbook playbooks/04-apps.yml      # deploy apps
```

After the run completes, `kubeconfig.yaml` is fetched to the repo root.

```bash
export KUBECONFIG=./kubeconfig.yaml
kubectl get nodes
kubectl -n homelab get pods,svc,ingress
```

---

## Accessing Services

| Service         | URL                                   | Notes                          |
|-----------------|---------------------------------------|--------------------------------|
| Jellyfin        | http://jellyfin.homelab.local         | Add AdGuard DNS rewrite or `/etc/hosts` |
| Website         | http://www.homelab.local              | Replace nginx ConfigMap with your site |
| AdGuard Home    | http://192.168.68.50:3000              | Admin UI — set password on first login |
| Traefik UI      | http://192.168.68.200:8080/dashboard/  | MetalLB gives Traefik .200     |

### Point your router's DNS at AdGuard

Set your router's DNS server (DHCP option 6) to **192.168.68.50**.
All homelab hostnames are pre-configured as rewrites in AdGuard.

---

## Customising the Website

Edit `ansible/roles/k3s_apps/files/website/configmap.yml` and replace the `index.html` content,
then re-run `ansible-playbook playbooks/04-apps.yml`.

For a proper site, replace the nginx Deployment with your actual container image.

## Adding More Services

1. Create a new directory under `ansible/roles/k3s_apps/files/<service>/`
2. Add `deployment.yml`, `service.yml`, `ingress.yml`
3. Add the hostname to AdGuard rewrites in `ansible/roles/adguard/templates/AdGuardHome.yaml.j2`
4. Re-run `ansible-playbook playbooks/04-apps.yml playbooks/03-adguard.yml`

---

## Resource Summary

| Node          | vCPU | RAM   | Storage             |
|---------------|------|-------|---------------------|
| k3s-master-1  | 4    | 8 GB  | 50 GB SSD           |
| k3s-worker-1  | 4    | 16 GB | 50 GB SSD           |
| k3s-worker-2  | 4    | 20 GB | 50 GB SSD + 2 TB HDD|
| adguard (LXC) | 2    | 1 GB  | 8 GB SSD            |
| **Total**     | **14** | **45 GB** | ~2.1 TB SSD + 2 TB HDD |
| **Available** | 2    | 19 GB | ~800 GB SSD + 2 TB HDD |

---

## Secrets Management

> **Never commit `terraform.tfvars` or `kubeconfig.yaml`** — both are in `.gitignore`.

For production hardening consider:
- [SOPS](https://github.com/mozilla/sops) + age encryption for Ansible secrets
- Terraform remote state in an S3-compatible backend (e.g. MinIO on Proxmox)
- Vault for dynamic secrets

---

## File Structure

```
homelab/
├── terraform/
│   ├── providers.tf           # bpg/proxmox provider
│   ├── variables.tf           # all input variables
│   ├── main.tf                # VMs + LXC resources
│   ├── outputs.tf             # IPs, inventory hint
│   └── terraform.tfvars.example
│
└── ansible/
    ├── ansible.cfg
    ├── inventory/
    │   └── hosts.yml
    ├── group_vars/
    │   ├── all.yml
    │   └── k3s_cluster.yml
    ├── playbooks/
    │   ├── site.yml           # master playbook
    │   ├── 01-common.yml
    │   ├── 02-k3s.yml
    │   ├── 03-adguard.yml
    │   └── 04-apps.yml
    └── roles/
        ├── common/            # OS baseline, sysctl, SSH hardening
        ├── k3s_master/        # k3s server, Helm, MetalLB, Traefik, cert-manager
        ├── k3s_worker/        # k3s agent, HDD format+mount, node labels
        ├── adguard/           # AdGuard Home binary + config
        └── k3s_apps/          # Jellyfin + website manifests
```
