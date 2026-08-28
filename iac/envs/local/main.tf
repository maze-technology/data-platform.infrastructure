terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kubeconfig_context
  }
}

locals {
  # Static in-cluster fallback so aws.rgw provider config never depends on
  # deferred Vault/module outputs (unknown provider → BucketAlreadyExists churn).
  rgw_in_cluster_endpoint = "http://rgw-service.rook-ceph.svc.cluster.local:80"

  rgw_s3_apply_endpoint = coalesce(
    var.rgw_s3_endpoint != "" ? var.rgw_s3_endpoint : null,
    local.rgw_in_cluster_endpoint,
  )

  vault_apply_address = coalesce(
    var.vault_address != "" ? var.vault_address : null,
    "http://vault.vault.svc.cluster.local:8200",
  )
}

provider "vault" {
  address          = local.vault_apply_address
  token            = var.vault_token
  skip_tls_verify  = var.vault_skip_tls_verify
  skip_child_token = true
}

# Dummy default AWS provider (unused — S3 uses aws.rgw). Region-only so
# provider config stays known without credentials.
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  shared_credentials_files    = []
  shared_config_files         = []
}

# AWS provider for S3 bucket management (Rook-Ceph RGW)
provider "aws" {
  alias = "rgw"

  endpoints {
    s3 = local.rgw_s3_apply_endpoint
  }

  # Credentials from environment variables (set after foundation bootstrap).
  # Region is required by the AWS provider but ignored by RGW.
  region = "us-east-1"

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  shared_credentials_files    = []
  shared_config_files         = []

  ec2_metadata_service_endpoint      = "http://169.254.169.254"
  ec2_metadata_service_endpoint_mode = "IPv4"
}

# Local smoke target: dedicated RGW bucket on the same Ceph (not off-cluster DR).
# Created during apply-services once aws.rgw credentials are exported from Vault.
resource "aws_s3_bucket" "cluster_backup" {
  count = var.backup_enabled ? 1 : 0

  provider      = aws.rgw
  bucket        = var.backup_s3_bucket
  force_destroy = true

  tags = {
    Name        = var.backup_s3_bucket
    Environment = "local"
    ManagedBy   = "opentofu"
    Purpose     = "velero-backups"
  }
}

resource "aws_s3_bucket_versioning" "cluster_backup" {
  count = var.backup_enabled ? 1 : 0

  provider = aws.rgw
  bucket   = aws_s3_bucket.cluster_backup[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

module "infrastructure_base" {
  source = "git::https://scm.maze.trading/data-platform/infrastructure-base.git?ref=v0.2.8"

  providers = {
    aws.rgw = aws.rgw
  }

  environment         = "local"
  cluster_name        = "local"
  cluster_domain      = var.cluster_domain
  cluster_public_ip   = var.cluster_public_ip
  enable_kind_cluster = true
  enable_cluster_dns  = true
  create_maze_ca      = true
  restrict_to_vpn     = true

  # Rook-Ceph — kind loop devices (never scan host disks)
  use_all_nodes       = false
  create_loop_devices = true
  allow_loop_devices  = true
  storage_nodes = [
    { name = "local-worker", devices = ["dm-1"], loop_device = "loop10" },
    { name = "local-worker2", devices = ["dm-2"], loop_device = "loop11" },
    { name = "local-worker3", devices = ["dm-0"], loop_device = "loop12" },
  ]
  local_block_osd_devices   = {}
  storage_class_device_sets = []
  mon_count                 = 1
  mgr_count                 = 1
  rgw_instances             = 1
  replication_size          = 1
  rook_resource_requests = {
    operator = { cpu = "50m", memory = "64Mi" }
    mon      = { cpu = "250m", memory = "1Gi" }
    mgr      = { cpu = "250m", memory = "256Mi" }
    osd      = { cpu = "500m", memory = "1Gi" }
    rgw      = { cpu = "250m", memory = "256Mi" }
  }
  rook_resource_limits = {
    operator = { cpu = "250m", memory = "256Mi" }
    mon      = { cpu = "500m", memory = "2Gi" }
    mgr      = { cpu = "500m", memory = "512Mi" }
    osd      = { cpu = "1", memory = "2Gi" }
    rgw      = { cpu = "500m", memory = "512Mi" }
  }
  osd_recovery_max_active  = 2
  osd_recovery_op_priority = 5
  osd_max_backfills        = 1
  rook_dashboard_enabled   = true
  rook_monitoring_enabled  = false

  # Cert-manager / ingress — Maze CA + NodePort (maze.local cannot use public ACME)
  letsencrypt_email          = ""
  letsencrypt_server         = "https://acme-staging-v02.api.letsencrypt.org/directory"
  cert_manager_replica_count = 1
  ingress_service_type       = "NodePort"
  ingress_node_port_http     = 30080
  ingress_node_port_https    = 30443
  ingress_replica_count      = 1
  ingress_port_suffix        = ""
  enable_ingress_metrics     = true

  # WireGuard
  vpn_subnet              = "10.8.0.0/24"
  wireguard_peers         = var.wireguard_peers
  wireguard_service_type  = "NodePort"
  wireguard_node_port     = 31820
  wireguard_storage_class = "standard"
  wireguard_storage_size  = "512Mi"

  # Keycloak
  keycloak_admin_username          = var.keycloak_admin_username
  keycloak_admin_password          = var.keycloak_admin_password
  bootstrap_admin                  = var.bootstrap_admin
  bootstrap_users                  = var.bootstrap_users
  keycloak_replica_count           = 1
  keycloak_storage_class           = "standard"
  keycloak_postgresql_storage_size = "2Gi"
  keycloak_production_mode         = true
  use_external_keycloak_database   = false

  # Vault
  vault_replica_count     = 1
  vault_enable_ha         = false
  vault_storage_backend   = "kubernetes"
  vault_enable_server_tls = false

  # Observability — reduced PVC sizes for kind
  prometheus_storage_size      = "3Gi"
  prometheus_retention         = "7d"
  grafana_storage_size         = "1Gi"
  loki_storage_size            = "1Gi"
  tempo_storage_size           = "2Gi"
  observability_storage_class  = "standard"
  loki_deployment_mode         = "single-binary"
  loki_chunks_cache_memory_mb  = 1024
  loki_results_cache_memory_mb = 128
  enable_promtail              = true

  # Argo CD
  argocd_replica_count = 1
  argocd_enable_ha     = false

  # GitLab — local-path storage (kind RBD mount fails); light replica profile
  use_external_gitlab_postgresql = false
  gitlab_storage_class           = "standard"
  gitaly_storage_class           = "standard"
  gitaly_storage_size            = "4Gi"
  gitlab_postgresql_storage_size = "3Gi"

  # Kellnr private Cargo registry
  enable_kellnr                  = true
  kellnr_postgresql_storage_size = "3Gi"
  kellnr_replica_count           = 1
  valkey_storage_size            = "1Gi"
  s3_force_destroy               = true
  install_gitlab_runner          = true
  gitlab_runner_replicas         = 1
  webservice_min_replicas        = 1
  webservice_max_replicas        = 1
  webservice_worker_processes    = 1
  shell_min_replicas             = 1
  shell_max_replicas             = 1
  kas_min_replicas               = 1
  kas_max_replicas               = 1
  registry_min_replicas          = 1
  registry_max_replicas          = 1

  # Backup — Velero + Kopia (encrypted, incremental) → local RGW bucket
  backup_enabled                     = var.backup_enabled
  backup_s3_bucket                   = var.backup_enabled ? aws_s3_bucket.cluster_backup[0].id : ""
  backup_s3_prefix                   = var.backup_s3_prefix
  backup_s3_region                   = "us-east-1"
  backup_s3_endpoint                 = local.rgw_in_cluster_endpoint
  backup_s3_force_path_style         = true
  backup_s3_insecure_skip_tls_verify = true
  backup_s3_access_key               = var.backup_s3_access_key
  backup_s3_secret_key               = var.backup_s3_secret_key
  backup_encryption_password         = var.backup_encryption_password
  backup_schedule_cron               = var.backup_schedule_cron
  backup_ttl                         = var.backup_ttl
  backup_object_sync_enabled         = var.backup_object_sync_enabled
  backup_object_sync_schedule_cron   = var.backup_object_sync_schedule_cron
}
