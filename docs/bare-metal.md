# Bare-metal Kubernetes bootstrap (OVH)

Prepares three dedicated servers and brings up a **3× control-plane + worker**
kubeadm cluster (stacked etcd) with **Cilium**.

## Inventory (not committed)

Hostnames and IPs live in a **local** file (gitignored):

```bash
cp scripts/bare-metal/inventory.env.example scripts/bare-metal/inventory.env
# fill BM0N_SSH, BM0N_PUBLIC, BM0N_PRIVATE, LB_FLOATING_IP, …
```

Or point at any file:

```bash
export BARE_METAL_INVENTORY=/path/to/inventory.env
```

Defaults in the example use documentation IPs (`example.invalid` / `203.0.113.0/24`);
scripts refuse to run until those are replaced.

Expected shape: three nodes with private NICs on a shared VLAN/CIDR (see
`VRACK_*` in the example), Rook OSD on a **non-OS** disk (e.g. `/dev/sdb`).

## Prerequisites

- SSH key (default `~/.ssh/ovh_maze`, or set `SSH_KEY`)
- Private networking already configured on each node
- Ubuntu 26.04 (or compatible) on all nodes

## UFW: pod → apiserver

`01-host-basics.sh` opens TCP **6443** from the pod CIDR (`10.244.0.0/16`, comment
`apiserver-pods`). Without that rule, ClusterIP DNAT keeps the pod source IP and UFW
drops kube-apiserver traffic — GitLab Runner jobs then fail with
`dial tcp …6443: i/o timeout`.

On nodes bootstrapped before that rule existed:

```bash
ufw allow from 10.244.0.0/16 to any port 6443 proto tcp comment 'apiserver-pods'
ufw reload
```

## Run order (from this repo)

```bash
export SSH_KEY=~/.ssh/ovh_maze
cp scripts/bare-metal/inventory.env.example scripts/bare-metal/inventory.env
# edit inventory.env

./scripts/bare-metal/01-host-basics.sh --remote
./scripts/bare-metal/02-containerd-kubeadm.sh --remote
./scripts/bare-metal/03-kubeadm-cluster.sh --remote
```

Or: `make bare-metal-bootstrap`

Artifacts land in `scripts/bare-metal/.cluster-state/` (gitignored):
- `admin.conf` — kubeconfig (server is the private control-plane endpoint)
- join command snippets

From a host without private routing, rewrite the kubeconfig server to a public
control-plane IP from your inventory:

```bash
# replace with BM01_PRIVATE / BM01_PUBLIC from inventory.env
sed -i "s#\${BM01_PRIVATE}:6443#\${BM01_PUBLIC}:6443#" \
  scripts/bare-metal/.cluster-state/admin.conf
export KUBECONFIG=$PWD/scripts/bare-metal/.cluster-state/admin.conf
kubectl get nodes
```

Control-plane taints are removed so all three nodes schedule workloads.

## Ingress / Load Balancer

Production is **VPN-only** on the public internet (see [public-surface.md](public-surface.md)):

- OVH Public Cloud LB (managed in OpenTofu `ovh_lb.tf`) exposes **UDP 31820** only
  (WireGuard NodePort) to the three bare-metal private IPs.
- Ingress-nginx is **ClusterIP**; app hostnames resolve via WireGuard **split-DNS**
  (systemd-resolved `~maze.trading` → CoreDNS) → that ClusterIP. There is no public
  HTTP/HTTPS listener. Peer configs must **not** set `DNS=` (that triggers
  `resolvconf -x` and breaks general internet); they use `resolvectl` PostUp hooks.
- Git over SSH uses CoreDNS name **`git-ssh.maze.trading`** → `gitlab-gitlab-shell`
  ClusterIP (never the public LB). Example SSH config: `HostName git-ssh.maze.trading`.
- TLS is Let's Encrypt **DNS-01** (OVH DNS webhook) — no ACME HTTP-01 on :80.
  Use a dedicated OVH consumer key limited to `/domain/zone/<domain>/*`, not the
  cloud-project OpenTofu key (`ovh_dns_consumer_key` in production tfvars).

DNS: `vpn.maze.trading` → LB floating IP via **public** DNS only (CoreDNS must not
override it to the ingress ClusterIP — that breaks the WireGuard endpoint after
connect). App names (`scm`, `auth`, `crates`, `git-ssh`, …) resolve through CoreDNS while on VPN.

## SSH access

SSH on the bare-metal nodes is **not** exposed to the public internet.

- Preferred: connect to WireGuard, then SSH to private IPs (`192.168.10.1` / `.2` / `.3`).
  Peer `AllowedIPs` must include the vRack CIDR (`192.168.0.0/16`) so those routes go
  through the tunnel — regenerate/re-import the peer config after OpenTofu updates it.
- Break-glass: the management jump host IP (`JUMP_IP`, set automatically when running
  `01-host-basics.sh --remote`) may still reach port 22. OVH IPMI/KVM remains the last resort.
- Bootstrap UFW allows SSH from the VPN subnet (`10.8.0.0/24`), pod CIDR (`10.244.0.0/16`
  for WireGuard hairpin), and `JUMP_IP` — never `Anywhere`.

## Identity

- **Daily SSO:** `bootstrap_admin` in the Keycloak **maze** realm (example: `admin`).
  Same email links GitLab `root` via OIDC. WireGuard peer name defaults to this username.
- **Keycloak break-glass:** `keycloak_admin_*` in the **master** realm only — offline password
  manager / Vault; not used for GitLab/Grafana/Argo day-to-day.

## Host maintenance

- Bootstrap enables **security-only** `unattended-upgrades` with **no automatic reboot**.
- Reboot nodes one at a time after `kubectl drain` (or later kured). Never reboot all three at once.
- See also [host-naming.md](host-naming.md) and [opentofu-state.md](opentofu-state.md).

## External backups

In-cluster **GitLab / Keycloak / Kellnr** CloudNativePG is covered by:

1. Velero/Kopia filesystem backups (PVC, including `*-pg-1`) → OVH bucket  
2. Scheduled **logical `pg_dump`** CronJobs (`postgres-dump-{gitlab,keycloak,kellnr}`) → same bucket under `logical/postgres/` (rclone crypt). Dump client image must be ≥ CNPG major (currently Postgres 18).

There is no CNPG continuous WAL archiving (`ScheduledBackup`) yet — recovery is dump +/or PVC restore.

GitLab Valkey is cache-only (safe to empty on restore). Gitaly + RGW object mirror cover repos/blobs separately.

Any remaining external/managed databases stay the operator’s responsibility.
