# OVH Public Cloud — Object Storage for production backups (GRA primary + SBG DR).
# PostgreSQL: Web Cloud Databases (manual) via terraform.tfvars — not provisioned here.
# Auth via env (preferred):
#   export OVH_ENDPOINT=ovh-eu
#   export OVH_APPLICATION_KEY=...
#   export OVH_APPLICATION_SECRET=...
#   export OVH_CONSUMER_KEY=...

provider "ovh" {
  # Credentials from env (preferred): OVH_ENDPOINT, OVH_APPLICATION_KEY,
  # OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY — or set ovh_* in tfvars via
  # a local OVH_CLI config. Empty string overrides in the provider block break env fallback.
  endpoint = var.ovh_endpoint
}

locals {
  ovh_project = var.ovh_cloud_project_id

  keycloak_pg_host = var.keycloak_postgresql_host
  keycloak_pg_port = var.keycloak_postgresql_port
  keycloak_pg_user = var.keycloak_postgresql_username
  keycloak_pg_db   = var.keycloak_postgresql_database
  keycloak_pg_pass = var.keycloak_postgresql_password

  gitlab_pg_host = var.gitlab_postgresql_host
  gitlab_pg_port = var.gitlab_postgresql_port
  gitlab_pg_user = var.gitlab_postgresql_username
  gitlab_pg_db   = var.gitlab_postgresql_database
  gitlab_pg_pass = var.gitlab_postgresql_password

  backup_s3_access_key = var.backup_s3_access_key != "" ? var.backup_s3_access_key : (var.backup_enabled ? ovh_cloud_project_user_s3_credential.backup[0].access_key_id : "")
  backup_s3_secret_key = var.backup_s3_secret_key != "" ? var.backup_s3_secret_key : (var.backup_enabled ? ovh_cloud_project_user_s3_credential.backup[0].secret_access_key : "")
  backup_s3_bucket     = var.backup_enabled ? ovh_cloud_project_storage.backup[0].name : ""
  backup_s3_endpoint   = var.backup_s3_endpoint != "" ? var.backup_s3_endpoint : "https://s3.${lower(var.ovh_object_storage_region)}.io.cloud.ovh.net"
  backup_s3_region     = lower(var.ovh_object_storage_region)

  backup_s3_dr_bucket   = var.backup_enabled ? ovh_cloud_project_storage.backup_dr[0].name : ""
  backup_s3_dr_endpoint = "https://s3.${lower(var.ovh_object_storage_dr_region)}.io.cloud.ovh.net"
  backup_s3_dr_region   = lower(var.ovh_object_storage_dr_region)
}

# -----------------------------------------------------------------------------
# Object Storage (Velero + rclone crypt mirror target)
# Primary: GRA — DR: SBG via OVH async replication
# -----------------------------------------------------------------------------

resource "ovh_cloud_project_user" "backup" {
  count = var.backup_enabled ? 1 : 0

  service_name = local.ovh_project
  description  = "maze-cluster-backup-s3"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "backup" {
  count = var.backup_enabled ? 1 : 0

  service_name = ovh_cloud_project_user.backup[0].service_name
  user_id      = ovh_cloud_project_user.backup[0].id
}

resource "ovh_cloud_project_user_s3_policy" "backup" {
  count = var.backup_enabled ? 1 : 0

  service_name = ovh_cloud_project_user.backup[0].service_name
  user_id      = ovh_cloud_project_user.backup[0].id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "RWPrimaryAndDrBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads",
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::${ovh_cloud_project_storage.backup[0].name}",
          "arn:aws:s3:::${ovh_cloud_project_storage.backup[0].name}/*",
          "arn:aws:s3:::${ovh_cloud_project_storage.backup_dr[0].name}",
          "arn:aws:s3:::${ovh_cloud_project_storage.backup_dr[0].name}/*",
        ]
      }
    ]
  })

  depends_on = [
    ovh_cloud_project_storage.backup,
    ovh_cloud_project_storage.backup_dr,
  ]
}

resource "ovh_cloud_project_storage" "backup_dr" {
  count = var.backup_enabled ? 1 : 0

  service_name = local.ovh_project
  region_name  = var.ovh_object_storage_dr_region
  name         = var.backup_s3_dr_bucket

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }

  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
    Purpose     = "cluster-backups-dr"
  }
}

resource "ovh_cloud_project_storage" "backup" {
  count = var.backup_enabled ? 1 : 0

  service_name = local.ovh_project
  region_name  = var.ovh_object_storage_region
  name         = var.backup_s3_bucket

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }

  replication = {
    rules = [
      {
        id       = "replicate-to-sbg"
        priority = 1
        status   = "enabled"
        filter   = {}
        destination = {
          name   = ovh_cloud_project_storage.backup_dr[0].name
          region = ovh_cloud_project_storage.backup_dr[0].region_name
        }
        delete_marker_replication = "enabled"
      }
    ]
  }

  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
    Purpose     = "cluster-backups"
  }

  lifecycle {
    precondition {
      condition     = length(var.backup_encryption_password) >= 16
      error_message = "When backup_enabled, set backup_encryption_password (≥16 chars) and store it offline."
    }
  }

  depends_on = [ovh_cloud_project_storage.backup_dr]
}

# One-shot catch-up for objects that existed before the replication rule.
# Destroying this resource only removes it from state; the OVH job keeps running.
resource "ovh_cloud_project_storage_replication_job" "backup_catchup" {
  count = var.backup_enabled ? 1 : 0

  service_name   = local.ovh_project
  region_name    = ovh_cloud_project_storage.backup[0].region_name
  container_name = ovh_cloud_project_storage.backup[0].name

  depends_on = [ovh_cloud_project_storage.backup]
}

# -----------------------------------------------------------------------------
# Object Storage for OpenTofu remote state (client-side encrypted at apply time)
# -----------------------------------------------------------------------------

resource "ovh_cloud_project_user" "tofu_state" {
  service_name = local.ovh_project
  description  = "maze-opentofu-state-s3"
  role_name    = "objectstore_operator"
}

resource "ovh_cloud_project_user_s3_credential" "tofu_state" {
  service_name = ovh_cloud_project_user.tofu_state.service_name
  user_id      = ovh_cloud_project_user.tofu_state.id
}

resource "ovh_cloud_project_storage" "tofu_state" {
  service_name = local.ovh_project
  region_name  = var.ovh_object_storage_region
  name         = var.tofu_state_s3_bucket

  versioning = {
    status = "enabled"
  }

  encryption = {
    sse_algorithm = "AES256"
  }

  tags = {
    Environment = "production"
    ManagedBy   = "opentofu"
    Purpose     = "opentofu-state"
  }
}

resource "ovh_cloud_project_user_s3_policy" "tofu_state" {
  service_name = ovh_cloud_project_user.tofu_state.service_name
  user_id      = ovh_cloud_project_user.tofu_state.id
  policy = jsonencode({
    Statement = [
      {
        Sid    = "RWStateBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads",
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
        ]
        Resource = [
          "arn:aws:s3:::${ovh_cloud_project_storage.tofu_state.name}",
          "arn:aws:s3:::${ovh_cloud_project_storage.tofu_state.name}/*",
        ]
      }
    ]
  })

  depends_on = [ovh_cloud_project_storage.tofu_state]
}
