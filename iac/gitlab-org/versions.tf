terraform {
  required_version = ">= 1.5.0"

  # Same OVH Object Storage backend as production; dedicated state key.
  # Credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (tofu_state user).
  # Partial config — see README.md and docs/opentofu-state.md for init flags.
  backend "s3" {
    key          = "gitlab-org/terraform.tfstate"
    use_lockfile = true # OVH S3 conditional writes (native .tflock)
  }

  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }

    state {
      method   = method.aes_gcm.state
      enforced = true
    }

    plan {
      method   = method.aes_gcm.state
      enforced = true
    }
  }

  required_providers {
    gitlab = {
      source  = "gitlabhq/gitlab"
      version = "~> 19.0"
    }
  }
}
