# infrastructure

Environment composition roots that pin and apply [`infrastructure-base`](https://github.com/maze-technology/infrastructure-base).

Each env under `iac/envs/*` is a thin OpenTofu root: providers, backends, tfvars, and a single `module "infrastructure_base"` call. Shared platform logic lives in the versioned base module. Renovate bumps the literal `ref=` when new tags land on `infrastructure-base`.

## Pinning infrastructure-base

In each env `main.tf` use a literal git tag (so Renovate can update it):

```hcl
module "infrastructure_base" {
  source = "git::https://github.com/maze-technology/infrastructure-base.git?ref=v0.1.0"

  providers = {
    aws.rgw = aws.rgw
  }

  # env-specific inputs...
}
```

After a pin change, re-run `make init ENV=<env>` so OpenTofu fetches the new module version.

## Layout

```
.
├── Makefile                 # kind, loop devices, two-stage apply
├── config/kind-config.yaml  # kind cluster definition
├── docs/                    # operational notes
└── iac/envs/
    ├── local/               # kind / maze.local
    └── production/          # bare metal / maze.trading
```

## Local quick start

```bash
cp iac/envs/local/terraform.tfvars.example iac/envs/local/terraform.tfvars
# edit secrets / cluster_public_ip

make local-setup          # kind-up
make init ENV=local
make apply ENV=local      # foundation + services (two-stage)
```

Useful helpers: `make setup-loop-devices`, `make prepull-ceph-image`, `make kind-status`.

Do **not** commit `terraform.tfvars`, `*.tfstate`, or `.terraform/`.

## Production (OVH bare metal)

Bootstrap Kubernetes on the dedicated servers first (see [docs/bare-metal.md](docs/bare-metal.md)):

```bash
export SSH_KEY=~/.ssh/ovh_maze
cp scripts/bare-metal/inventory.env.example scripts/bare-metal/inventory.env
# fill SSH hosts / IPs (inventory.env is gitignored)
make bare-metal-bootstrap   # host basics + kubeadm HA + Cilium
```

Then apply the platform:

```bash
cp iac/envs/production/terraform.tfvars.example iac/envs/production/terraform.tfvars
# fill ovh_cloud_project_id, OVH API env keys, backup_encryption_password, bootstrap admins, cluster_domain=maze.trading, etc.

make init ENV=production
make apply ENV=production
```

Ingress should sit behind WireGuard (VPN-only). The OVH Public Cloud LB VIP
(`LB_FLOATING_IP`) exposes **UDP 31820** only; TLS is Let's Encrypt DNS-01.
## Providers

This repo owns provider configuration:

| Provider | Role |
|----------|------|
| `kubernetes` / `helm` | Target cluster via kubeconfig |
| `vault` | Address/token (port-forward or VPN) |
| `aws` (default) | Dummy region-only config (unused) |
| `aws.rgw` | S3-compatible Rook RGW endpoint (required by the base module) |

`aws.rgw` is passed into the module via `providers = { aws.rgw = aws.rgw }` (`configuration_aliases` in the base module). Prefer an explicit `rgw_s3_endpoint` / Vault address at apply time (Makefile port-forwards when unset).

## Cluster backup

Velero + Kopia (encrypted PVC backups) and rclone crypt mirror of RGW buckets (GitLab, Loki) into the same backup store. One password: `backup_encryption_password`.

| Env | Object store | Notes |
|-----|--------------|-------|
| `local` | RGW bucket `cluster-backup-local` (same Ceph) | Smoke only. Makefile passes RGW keys during `apply-services`. |
| `production` | OVH Object Storage (S3) | **On by default.** OpenTofu creates the GRA primary bucket (via `ovh_cloud_project_storage`) and an **SBG DR** bucket. GRA→SBG uses OVH async replication. Set OVH keys + `backup_encryption_password` in tfvars. |

Keycloak and GitLab use in-cluster Postgres; their PVCs are covered by Velero/Kopia (same as other stateful apps).

**Restore from DR:** retarget tools to the SBG endpoint (`ovh_backup_dr_endpoint` output) with the same keys/password.

## Related

- [`infrastructure-base`](https://github.com/maze-technology/infrastructure-base) — versioned root module
- [docs/gitlab-container-security.md](docs/gitlab-container-security.md) — cosign + Kyverno signed-image policy
