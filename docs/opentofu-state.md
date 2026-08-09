# OpenTofu state (production)

## Today → target

State starts **local** on the management host (`iac/envs/production/terraform.tfstate`), then moves to **OVH Object Storage** with **client-side encryption** (same model as `configuration/`).

Bucket/user are managed in [`ovh.tf`](../iac/envs/production/ovh.tf) (`maze-opentofu-state-production`).

## Passphrase

```bash
# already generated on the management VPS (gitignored):
#   infrastructure/secrets/tofu-state-passphrase.txt
export TF_VAR_state_encryption_passphrase="$(cat secrets/tofu-state-passphrase.txt)"
```

Store a copy offline. Losing it makes state unrecoverable.

## Migrate local → OVH (after bucket exists in state)

```bash
cd iac/envs/production
eval "$(tofu output -raw tofu_state_backend_env)"  # once outputs exist; or set manually:

export AWS_ACCESS_KEY_ID=...      # from ovh_cloud_project_user_s3_credential.tofu_state
export AWS_SECRET_ACCESS_KEY=...
export TF_VAR_state_encryption_passphrase="$(cat ../../../secrets/tofu-state-passphrase.txt)"

# Add to main.tf:
#   backend "s3" { key = "production/terraform.tfstate" }

tofu init -migrate-state \
  -backend-config="bucket=maze-opentofu-state-production" \
  -backend-config="region=gra" \
  -backend-config="endpoints={s3=\"https://s3.gra.io.cloud.ovh.net\"}" \
  -backend-config="use_path_style=true" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="skip_region_validation=true" \
  -backend-config="skip_requesting_account_id=true"
```

Then remove the `unencrypted` encryption fallback and set `enforced = true` on state/plan.

No DynamoDB lock on OVH — avoid concurrent applies from two hosts.
