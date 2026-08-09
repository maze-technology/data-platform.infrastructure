# OpenTofu state (production)

Production state lives in **OVH Object Storage** (`maze-opentofu-state-production`) with **client-side AES-GCM encryption** (`enforced = true`).

Bucket/user/policy: [`ovh.tf`](../iac/envs/production/ovh.tf). Backend key: `production/terraform.tfstate`.

## Required env (management host)

```bash
# gitignored on the VPS:
source secrets/tofu-state-env.sh
# or:
export AWS_ACCESS_KEY_ID=...       # tofu_state S3 user
export AWS_SECRET_ACCESS_KEY=...
export TF_VAR_state_encryption_passphrase="$(cat secrets/tofu-state-passphrase.txt)"
```

Store passphrase + state keys offline. Losing the passphrase makes state unrecoverable.

For cluster applies you still need Vault/RGW port-forwards and the **RGW** keys on the `aws.rgw` provider (set in provider block / tfvars — not the same as backend `AWS_*`).

## Init (already migrated)

```bash
cd iac/envs/production
source ../../../secrets/tofu-state-env.sh

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
```

Native S3 locking is enabled (`use_lockfile = true`): OpenTofu writes a sibling `.tflock` object via OVH conditional writes. Still avoid overlapping applies from two hosts if a lock is stuck — delete `production/terraform.tfstate.tflock` only after confirming no apply is running.

## Local backup

A pre-migrate copy remains on the VPS as `terraform.tfstate.pre-remote-*.Z` (gitignored). Safe to delete after you confirm remote reads work.
