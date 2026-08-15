# GitLab org groups (Maze)

Separate OpenTofu root for **org-wide GitLab groups** (former GitHub teams). Kept out of `iac/envs/production` so applies do not need the GitLab provider, kubeconfig, or Vault — and out of **infrastructure-base** (Maze-specific roster).

## Groups

| Path | Role |
|------|------|
| `engineers` | Parent engineer roster |
| `engineers/infrastructure-engineers` | Infrastructure |
| `engineers/release-engineers` | Release |
| `project-managers` | Project managers (top-level sibling) |

No user memberships yet (SSO later). Toggle with `gitlab_groups_enabled` (default `true`).

`engineers` / `admins` may already exist from the production `gitlab-ci-cosign` bootstrap (OIDC ACL). If `engineers` already exists, import before apply:

```bash
tofu import 'gitlab_group.engineers[0]' engineers
```

## Why a separate root

Production (`iac/envs/production`) has no `gitlab` provider today. Adding one would pull GitLab into every cluster apply. This root uses its own state key: `gitlab-org/terraform.tfstate` in the same OVH bucket and encryption passphrase as production.

## Apply

```bash
cd iac/gitlab-org
source ../../secrets/tofu-state-env.sh   # AWS_* + TF_VAR_state_encryption_passphrase

export GITLAB_TOKEN=...                 # or TF_VAR_gitlab_token
# reachable API (VPN): https://scm.maze.trading/api/v4

tofu init \
  -backend-config="bucket=maze-opentofu-state-production" \
  -backend-config="region=gra" \
  -backend-config="endpoints={s3=\"https://s3.gra.io.cloud.ovh.net\"}" \
  -backend-config="use_path_style=true" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_region_validation=true" \
  -backend-config="skip_requesting_account_id=true" \
  -backend-config="skip_s3_checksum=true"

tofu plan
tofu apply
```

See also [docs/opentofu-state.md](../../docs/opentofu-state.md).
