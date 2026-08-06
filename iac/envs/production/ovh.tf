# OVH Public Cloud — managed PostgreSQL + Object Storage for production
# Auth via env (preferred):
#   export OVH_ENDPOINT=ovh-eu
#   export OVH_APPLICATION_KEY=...
#   export OVH_APPLICATION_SECRET=...
#   export OVH_CONSUMER_KEY=...
# Or set ovh_* variables in terraform.tfvars (gitignored).

provider "ovh" {
  # Credentials from env (preferred): OVH_ENDPOINT, OVH_APPLICATION_KEY,
  # OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY — or set ovh_* in tfvars via
  # a local OVH_CLI config. Empty string overrides in the provider block break env fallback.
  endpoint = var.ovh_endpoint
}

locals {
  ovh_project = var.ovh_cloud_project_id

  pg_node_count = ({
    essential  = 1
    business   = 2
    enterprise = 3
  })[var.ovh_postgresql_plan]

  pg_endpoints = [
    for e in ovh_cloud_project_database.maze.endpoints : e
    if e.component == "postgresql"
  ]
  pg_endpoint = local.pg_endpoints[0]

  keycloak_pg_host = var.keycloak_postgresql_host != "" ? var.keycloak_postgresql_host : local.pg_endpoint.domain
  keycloak_pg_port = var.keycloak_postgresql_port > 0 ? var.keycloak_postgresql_port : local.pg_endpoint.port
  keycloak_pg_pass = var.keycloak_postgresql_password != "" ? var.keycloak_postgresql_password : ovh_cloud_project_database_postgresql_user.keycloak.password

  gitlab_pg_host = var.gitlab_postgresql_host != "" ? var.gitlab_postgresql_host : local.pg_endpoint.domain
  gitlab_pg_port = var.gitlab_postgresql_port > 0 ? var.gitlab_postgresql_port : local.pg_endpoint.port
  gitlab_pg_pass = var.gitlab_postgresql_password != "" ? var.gitlab_postgresql_password : ovh_cloud_project_database_postgresql_user.gitlab.password

  backup_s3_access_key = var.backup_s3_access_key != "" ? var.backup_s3_access_key : (var.backup_enabled ? ovh_cloud_project_user_s3_credential.backup[0].access_key_id : "")
  backup_s3_secret_key = var.backup_s3_secret_key != "" ? var.backup_s3_secret_key : (var.backup_enabled ? ovh_cloud_project_user_s3_credential.backup[0].secret_access_key : "")
  backup_s3_bucket     = var.backup_enabled ? ovh_cloud_project_storage.backup[0].name : ""
  backup_s3_endpoint   = var.backup_s3_endpoint != "" ? var.backup_s3_endpoint : "https://s3.${lower(var.ovh_object_storage_region)}.io.cloud.ovh.net"
  backup_s3_region     = lower(var.ovh_object_storage_region)
}

# -----------------------------------------------------------------------------
# Managed PostgreSQL (shared cluster: Keycloak + GitLab databases/users)
# -----------------------------------------------------------------------------

resource "ovh_cloud_project_database" "maze" {
  service_name = local.ovh_project
  description  = "maze-trading-postgresql"
  engine       = "postgresql"
  version      = var.ovh_postgresql_version
  plan         = var.ovh_postgresql_plan
  flavor       = var.ovh_postgresql_flavor

  dynamic "nodes" {
    for_each = range(local.pg_node_count)
    content {
      region = var.ovh_postgresql_region
    }
  }

  dynamic "ip_restrictions" {
    for_each = var.ovh_database_allowed_cidrs
    content {
      description = ip_restrictions.value.description
      ip          = ip_restrictions.value.cidr
    }
  }

  deletion_protection = true

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }
}

resource "ovh_cloud_project_database_database" "keycloak" {
  service_name = ovh_cloud_project_database.maze.service_name
  engine       = ovh_cloud_project_database.maze.engine
  cluster_id   = ovh_cloud_project_database.maze.id
  name         = "keycloak"
}

resource "ovh_cloud_project_database_database" "gitlab" {
  service_name = ovh_cloud_project_database.maze.service_name
  engine       = ovh_cloud_project_database.maze.engine
  cluster_id   = ovh_cloud_project_database.maze.id
  name         = "gitlabhq_production"
}

resource "ovh_cloud_project_database_postgresql_user" "keycloak" {
  service_name = ovh_cloud_project_database.maze.service_name
  cluster_id   = ovh_cloud_project_database.maze.id
  name         = "keycloak"

  depends_on = [ovh_cloud_project_database_database.keycloak]
}

resource "ovh_cloud_project_database_postgresql_user" "gitlab" {
  service_name = ovh_cloud_project_database.maze.service_name
  cluster_id   = ovh_cloud_project_database.maze.id
  name         = "gitlab"

  depends_on = [ovh_cloud_project_database_database.gitlab]
}

# -----------------------------------------------------------------------------
# Object Storage (Velero + rclone crypt mirror target)
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
}
