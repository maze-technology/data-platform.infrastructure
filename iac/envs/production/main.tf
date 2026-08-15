terraform {
  required_version = ">= 1.5.0"

  # OVH Object Storage (S3). Credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  # (tofu_state user). Partial config — see docs/opentofu-state.md for init flags.
  backend "s3" {
    key          = "production/terraform.tfstate"
    use_lockfile = true # OVH S3 conditional writes (native .tflock)
  }

  # Client-side encryption — remote object storage never sees plaintext state/plan.
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

  # Explicit RGW keys — AWS_* env is reserved for OVH OpenTofu state backend.
  access_key = var.rgw_s3_access_key
  secret_key = var.rgw_s3_secret_key

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
  # infrastructure-base v0.1.38 — Kellnr Cargo registry (+ prior GitLab/Maven fixes)
  source = "git::https://github.com/maze-technology/infrastructure-base.git?ref=v0.1.38"

  providers = {
    aws.rgw = aws.rgw
  }

  environment         = "production"
  cluster_name        = var.cluster_name
  cluster_domain      = var.cluster_domain
  enable_kind_cluster = false
  enable_cluster_dns  = true
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

  # Cert-manager — Let's Encrypt DNS-01 via OVH (no public HTTP)
  letsencrypt_email          = var.letsencrypt_email
  letsencrypt_server         = "https://acme-v02.api.letsencrypt.org/directory"
  cert_manager_replica_count = 3
  acme_solver                = "dns01"
  ovh_dns_application_key    = var.ovh_application_key
  ovh_dns_application_secret = var.ovh_application_secret
  ovh_dns_consumer_key       = var.ovh_consumer_key
  ovh_dns_endpoint_name      = var.ovh_endpoint != "" ? var.ovh_endpoint : "ovh-eu"
  ovh_dns_webhook_group_name = "acme.${var.cluster_domain}"

  # Ingress — ClusterIP only (reachable via WireGuard + CoreDNS, not the public LB)
  ingress_service_type   = "ClusterIP"
  ingress_replica_count  = 3
  enable_ingress_metrics = true

  # WireGuard — NodePort UDP behind OVH Public Cloud LB
  vpn_subnet             = var.vpn_subnet
  wireguard_server_url   = var.wireguard_server_url
  wireguard_peers        = var.wireguard_peers
  wireguard_allowed_ips  = var.wireguard_allowed_ips
  wireguard_service_type = "NodePort"
  wireguard_node_port    = var.wireguard_node_port

  # Keycloak — OVH managed PostgreSQL (provisioned in ovh.tf)
  keycloak_admin_username = var.keycloak_admin_username
  keycloak_admin_password = var.keycloak_admin_password
  bootstrap_admin         = var.bootstrap_admin
  bootstrap_users         = var.bootstrap_users
  keycloak_replica_count  = 2
  # In-cluster Bitnami Postgres (Web Cloud dropped — GitLab already needs schemas;
  # keep one PG pattern for both apps).
  use_external_keycloak_database   = false
  keycloak_postgresql_storage_size = "20Gi"

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

  # GitLab — in-cluster Postgres (Web Cloud PG forbids CREATE SCHEMA; GitLab needs
  # gitlab_partitions_* schemas). Keycloak uses in-cluster PG as well.
  use_external_gitlab_postgresql = false
  gitlab_postgresql_username     = local.gitlab_pg_user
  gitlab_postgresql_database     = local.gitlab_pg_db
  gitlab_postgresql_password     = local.gitlab_pg_pass
  gitlab_postgresql_ssl          = false
  gitlab_postgresql_storage_size = "50Gi"
  # Encrypted class needs CSI KMS ConfigMap wiring; use plain RBD until that lands.
  gitaly_storage_class    = "rook-ceph-block"
  gitaly_storage_size     = "100Gi"
  valkey_storage_size     = "8Gi"
  s3_force_destroy        = false
  webservice_min_replicas = 2
  webservice_max_replicas = 4

  # Kellnr private Cargo registry (crates.<domain>)
  enable_kellnr                   = true
  kellnr_postgresql_storage_size  = "10Gi"
  kellnr_replica_count            = 1

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
  backup_postgres_dump_enabled       = var.backup_postgres_dump_enabled
  backup_postgres_dump_schedule_cron = var.backup_postgres_dump_schedule_cron
  backup_postgres_dump_prefix        = var.backup_postgres_dump_prefix
  backup_postgres_dump_targets = var.backup_enabled ? [
    {
      name     = "gitlab"
      host     = "gitlab-postgresql.gitlab.svc.cluster.local"
      port     = 5432
      user     = var.gitlab_postgresql_username
      database = var.gitlab_postgresql_database
      # nonsensitive so backup module for_each keys are usable; secret still only in-cluster
      password = nonsensitive(var.gitlab_postgresql_password)
    },
    {
      name     = "keycloak"
      host     = "keycloak-postgresql.keycloak.svc.cluster.local"
      port     = 5432
      user     = "bn_keycloak"
      database = "bitnami_keycloak"
      password = nonsensitive(var.keycloak_postgresql_password)
    },
    {
      name     = "kellnr"
      host     = "kellnr-postgresql.kellnr.svc.cluster.local"
      port     = 5432
      user     = "kellnr"
      database = "kellnr"
      password = nonsensitive(module.infrastructure_base.kellnr_postgresql_password)
    },
  ] : []

  depends_on = [
    ovh_cloud_project_storage.backup,
    ovh_cloud_project_storage.backup_dr,
    ovh_cloud_project_user_s3_credential.backup,
  ]
}
