terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.23"
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
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.1"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kubeconfig_context
  }
}

locals {
  rgw_in_cluster_endpoint = "http://rgw-service.rook-ceph.svc.cluster.local:80"

  rgw_s3_apply_endpoint = coalesce(
    var.rgw_s3_endpoint != "" ? var.rgw_s3_endpoint : null,
    local.rgw_in_cluster_endpoint,
  )
}

provider "vault" {
  address          = var.vault_address
  skip_tls_verify  = var.vault_skip_tls_verify
  skip_child_token = true
  token            = var.vault_token
}

# Dummy default AWS provider (unused — S3 uses aws.rgw).
provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  shared_credentials_files    = []
  shared_config_files         = []
}

provider "aws" {
  alias = "rgw"

  endpoints {
    s3 = local.rgw_s3_apply_endpoint
  }

  region                      = "us-east-1"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
  shared_credentials_files    = []
  shared_config_files         = []
}

module "infrastructure_base" {
  # Pin to commit until infrastructure-base PR #6 is merged + tagged as v0.1.4
  source = "git::https://github.com/maze-technology/infrastructure-base.git?ref=4debbc1"

  providers = {
    aws.rgw = aws.rgw
  }

  environment         = "production"
  cluster_name        = var.cluster_name
  cluster_domain      = var.cluster_domain
  enable_kind_cluster = false
  enable_cluster_dns  = false
  create_maze_ca      = false
  restrict_to_vpn     = true

  # Rook-Ceph — bare metal OSDs (never include the OS disk)
  use_all_nodes            = false
  create_loop_devices      = false
  allow_loop_devices       = false
  storage_nodes            = var.storage_nodes
  mon_count                = 3
  mgr_count                = 1
  rgw_instances            = 2
  replication_size         = 3
  osd_recovery_max_active  = 3
  osd_recovery_op_priority = 3
  osd_max_backfills        = 1
  rook_monitoring_enabled  = false

  # Cert-manager / ingress — Let's Encrypt + NodePort (OVH Public Cloud LB → node :30080/:30443)
  letsencrypt_email          = var.letsencrypt_email
  letsencrypt_server         = "https://acme-v02.api.letsencrypt.org/directory"
  cert_manager_replica_count = 3
  ingress_service_type       = "NodePort"
  ingress_node_port_http     = 30080
  ingress_node_port_https    = 30443
  ingress_replica_count      = 3
  enable_ingress_metrics     = true

  # WireGuard — NodePort UDP (no MetalLB; point vpn.<domain> at a node public IP or UDP LB)
  vpn_subnet             = var.vpn_subnet
  wireguard_server_url   = var.wireguard_server_url
  wireguard_peers        = var.wireguard_peers
  wireguard_service_type = "NodePort"
  wireguard_node_port    = 31820

  # Keycloak — OVH managed PostgreSQL (provisioned in ovh.tf)
  keycloak_admin_username        = var.keycloak_admin_username
  keycloak_admin_password        = var.keycloak_admin_password
  bootstrap_admin                = var.bootstrap_admin
  bootstrap_users                = var.bootstrap_users
  keycloak_replica_count         = 2
  use_external_keycloak_database = true
  keycloak_postgresql_host       = local.keycloak_pg_host
  keycloak_postgresql_port       = local.keycloak_pg_port
  keycloak_postgresql_username   = ovh_cloud_project_database_postgresql_user.keycloak.name
  keycloak_postgresql_database   = ovh_cloud_project_database_database.keycloak.name
  keycloak_postgresql_password   = local.keycloak_pg_pass
  keycloak_postgresql_ssl        = true

  # Vault HA on Rook RBD
  vault_replica_count   = 3
  vault_enable_ha       = true
  vault_storage_backend = "file"
  vault_storage_size    = "10Gi"

  # Observability — production sizing
  prometheus_storage_size = "500Gi"
  grafana_storage_size    = "100Gi"
  loki_storage_size       = "1Ti"
  loki_deployment_mode    = "scalable"

  # Argo CD HA
  argocd_replica_count = 3
  argocd_enable_ha     = true

  # GitLab — external PostgreSQL + encrypted Gitaly
  use_external_gitlab_postgresql = true
  gitlab_postgresql_host         = local.gitlab_pg_host
  gitlab_postgresql_port         = local.gitlab_pg_port
  gitlab_postgresql_username     = ovh_cloud_project_database_postgresql_user.gitlab.name
  gitlab_postgresql_database     = ovh_cloud_project_database_database.gitlab.name
  gitlab_postgresql_password     = local.gitlab_pg_pass
  gitlab_postgresql_ssl          = true
  gitaly_storage_size            = "100Gi"
  valkey_storage_size            = "8Gi"
  s3_force_destroy               = false
  webservice_min_replicas        = 2
  webservice_max_replicas        = 4

  # Backup — Velero + Kopia + RGW rclone crypt → OVH Object Storage (ovh.tf)
  backup_enabled                     = var.backup_enabled
  backup_s3_bucket                   = local.backup_s3_bucket
  backup_s3_prefix                   = var.backup_s3_prefix
  backup_s3_region                   = local.backup_s3_region
  backup_s3_endpoint                 = local.backup_s3_endpoint
  backup_s3_force_path_style         = true
  backup_s3_insecure_skip_tls_verify = false
  backup_s3_access_key               = local.backup_s3_access_key
  backup_s3_secret_key               = local.backup_s3_secret_key
  backup_encryption_password         = var.backup_encryption_password
  backup_schedule_cron               = var.backup_schedule_cron
  backup_ttl                         = var.backup_ttl
  backup_object_sync_enabled         = var.backup_object_sync_enabled
  backup_object_sync_schedule_cron   = var.backup_object_sync_schedule_cron

  depends_on = [
    ovh_cloud_project_database.maze,
    ovh_cloud_project_database_database.keycloak,
    ovh_cloud_project_database_database.gitlab,
    ovh_cloud_project_database_postgresql_user.keycloak,
    ovh_cloud_project_database_postgresql_user.gitlab,
    ovh_cloud_project_storage.backup,
    ovh_cloud_project_user_s3_credential.backup,
  ]
}
