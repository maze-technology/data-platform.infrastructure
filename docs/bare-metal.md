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

OpenTofu production currently uses `LoadBalancer` for ingress. With a cloud LB
in front of the nodes, switch ingress to **NodePort** or **hostNetwork** and
point LB members at each node's private IP `:80`/`:443`. DNS should target
`LB_FLOATING_IP` from inventory.

MetalLB is **not** required when using an external cloud LB.

## External backups

Managed PostgreSQL (and any other resource outside this stack) backups remain
the responsibility of the person running the infrastructure.
