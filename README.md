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
├── Jellyfin     — media server  (https://jellyfin.home.prateeksavanur.dev)
├── Website      — nginx site    (https://www.home.prateeksavanur.dev)
├── Homelert     — alerting → Telegram (https://homelert.home.prateeksavanur.dev, ArgoCD-managed)
├── DeployGuard  — deployment tracking (https://deployguard.home.prateeksavanur.dev, ArgoCD-managed)
├── Vaultwarden  — password manager   (https://vault.home.prateeksavanur.dev, ArgoCD-managed, LAN/Tailscale only)
└── tg-jellyfin-sync — imports media posted to a Telegram channel into Jellyfin (ArgoCD-managed, no UI)

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
| Jellyfin        | https://jellyfin.home.prateeksavanur.dev         | Media server |
| Website         | https://www.home.prateeksavanur.dev              | Replace nginx ConfigMap with your site |
| Homelert        | https://homelert.home.prateeksavanur.dev         | Alert dashboard — deployed by ArgoCD from the homelert repo |
| DeployGuard     | https://deployguard.home.prateeksavanur.dev      | Deployment history & health — password: `deployguard_admin_password` |
| Vaultwarden     | https://vault.home.prateeksavanur.dev            | Passwords & API keys — Bitwarden apps, LAN/Tailscale only |
| AdGuard Home    | http://192.168.68.50:3000              | Admin UI — set password on first login |
| Traefik UI      | http://192.168.68.200:8080/dashboard/  | MetalLB gives Traefik .200     |

### Point your router's DNS at AdGuard

Set your router's DNS server (DHCP option 6) to **192.168.68.50**.
All homelab hostnames are pre-configured as rewrites in AdGuard.

### HTTPS

Homelab services live under `home.prateeksavanur.dev`, a subdomain with **no public DNS records**: only AdGuard
resolves it (wildcard rewrite → Traefik at `192.168.68.200`). cert-manager gets a Let's Encrypt
wildcard cert for `*.home.prateeksavanur.dev` using a Cloudflare DNS-01 challenge, and Traefik serves it as its
default cert, so every Ingress gets trusted HTTPS with no `tls:` block. HTTP redirects to HTTPS.

Set `cloudflare_dns_api_token` in `group_vars/k3s_cluster.yml` (Cloudflare → API Tokens →
"Edit zone DNS" template, zone `prateeksavanur.dev`), then run `playbooks/02-k3s.yml`.

### Access `*.home.prateeksavanur.dev` over Tailscale

Remote tailnet devices don't use AdGuard and can't reach `192.168.68.x` by default.
`k3s-master-1` advertises `192.168.68.0/24` as a subnet route (`tailscale_advertise_routes`
in `hosts.yml`, applied by `playbooks/06-tunnel.yml`). Then, in the Tailscale admin console:

1. **Machines → k3s-master-1 → Edit route settings** → approve `192.168.68.0/24`
2. **DNS → Nameservers → Add nameserver → Custom** → `192.168.68.50`,
   enable **Restrict to domain** → `home.prateeksavanur.dev`
3. Remote Linux clients: `sudo tailscale set --accept-routes` (other platforms accept routes by default).
   Never enable it on the homelab nodes themselves — they are on that LAN and it breaks their networking.

---

## Homelert (alerts)

Homelert lives in its own repo (`homelert_repo_url`); ArgoCD syncs its `kubernetes/` folder
via `k8s/apps/homelert.yml`. Only the Secret is created here, by `playbooks/05-argocd.yml`:

1. Fill in `homelert_telegram_bot_token` / `homelert_telegram_chat_id` (and optionally the
   `homelert_proxmox_*` vars) in `ansible/inventory/group_vars/k3s_cluster.yml`
2. `ansible-playbook playbooks/05-argocd.yml`

Images are built by GitHub Actions in the homelert repo (`.github/workflows/deploy.yml`), which
pins the new tag in `kubernetes/deployment.yaml` — ArgoCD rolls it out automatically.

Webhooks from inside the cluster: `http://homelert.homelert.svc.cluster.local/webhook/<source>`

---

## DeployGuard (deployment tracking)

DeployGuard lives in its own repo (`deployguard_repo_url`); ArgoCD syncs its `kubernetes/` folder
via `k8s/apps/deployguard.yml`. It records every Argo CD sync as a deployment, links it to the
previous one (commits / diff), verifies the app's health afterwards and alerts on failures.

```
Argo CD sync ──(Notifications webhook)──▶ DeployGuard ──▶ health-checks the app in-cluster
                                               │
                     failed / rolled back / unhealthy / down
                                               ▼
                               Homelert (rule "DeployGuard") ──▶ Telegram
```

Setup (secrets are generated into `group_vars/k3s_cluster.yml`, which stays out of git):

1. Push the DeployGuard repo and set `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` repo secrets —
   its GitHub Actions workflow builds the image and pins the tag in `kubernetes/deployment.yaml`
2. Check the `deployguard_*` vars in `ansible/inventory/group_vars/k3s_cluster.yml`
3. `ansible-playbook playbooks/05-argocd.yml` — enables Argo CD Notifications, creates
   `deployguard-secrets` + `argocd-notifications-secret`, and adds the AdGuard DNS rewrite
4. `ansible-playbook playbooks/03-adguard.yml` if AdGuard wasn't reloaded

Which apps are tracked and their health-check URLs are declared in the DeployGuard repo's
`kubernetes/configmap.yaml` (project slug = Argo CD Application name, environment = `homelab`).
Apps not listed there are still tracked — they're created on their first sync.

---

## Vaultwarden (passwords & secrets)

Self-hosted Bitwarden-compatible server, deployed by ArgoCD from `k8s/manifests/vaultwarden`
via `k8s/apps/vaultwarden.yml`. It lives under `home.prateeksavanur.dev`, so it is reachable only
from the LAN or the tailnet — **never add it to the Cloudflare Tunnel.**

Setup:

1. Generate an admin token hash and set `vaultwarden_admin_token` (single-quoted) in
   `ansible/inventory/group_vars/k3s_cluster.yml`:
   ```bash
   docker run --rm -it vaultwarden/server:1.37.4 /vaultwarden hash
   ```
   Keep the plaintext admin password you typed — that is what you enter at `/admin`.
2. `ansible-playbook playbooks/05-argocd.yml` — creates `vaultwarden-secrets`; ArgoCD syncs the app
3. Open `https://vault.home.prateeksavanur.dev/admin` → **Users → Invite User** (your email),
   then go to `https://vault.home.prateeksavanur.dev` → **Create account** with that email.
   Public sign-ups stay disabled; no SMTP is needed for invites.
4. In the vault: **Settings → Security → Two-step login** → enable an authenticator app.
5. iPhone: install Tailscale + Bitwarden → on the login screen choose **Self-hosted** →
   server URL `https://vault.home.prateeksavanur.dev`. Enable **Settings → Passwords →
   AutoFill → Bitwarden**. The app keeps an offline copy; Tailscale is only needed to sync.

Backups: the `vaultwarden-backup` CronJob runs nightly at 03:30, snapshots the SQLite DB
(+ RSA keys, attachments) and writes `vaultwarden-<timestamp>.tar.gz` to
`/mnt/media/backups/vaultwarden` on k3s-worker-2's HDD, keeping 30 days. That survives SSD/PVC
loss but **not** loss of the Proxmox host — copy that folder offsite as well.

```bash
kubectl -n vaultwarden create job --from=cronjob/vaultwarden-backup manual-backup   # test it
```

Restore: scale the Deployment to 0, extract a tarball over the PVC's `/data`
(remove `db.sqlite3-wal`/`-shm` first), scale back to 1.

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
        ├── k3s_apps/          # Jellyfin + website manifests
        ├── homelert/          # homelert-secrets (Telegram/Proxmox) for the ArgoCD-managed app
        ├── deployguard/       # deployguard-secrets + argocd-notifications-secret
        └── vaultwarden/       # vaultwarden-secrets (admin token) for the ArgoCD-managed app
```

## Visual Diagram

<img width="5400" height="6220" alt="diagram" src="https://github.com/user-attachments/assets/0420284d-e7b4-4b52-ba5a-248430d71d30" />

