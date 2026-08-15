variable "cluster_name" {
  description = "Kubernetes cluster name (must match kubeconfig context naming)"
  type        = string
  default     = "production"
}

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu client-side state/plan encryption (TF_VAR_state_encryption_passphrase). Store offline — loss = unrecoverable state."
  type        = string
  sensitive   = true
}

variable "cluster_domain" {
  description = "Base domain for all cluster services (e.g. maze.trading). DNS must resolve auth.<domain>, scm.<domain>, etc. to the cluster LB."
  type        = string
  default     = "maze.trading"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig for the OVH bare metal Kubernetes cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubectl context for the production cluster (set after K8s bootstrap on bare metal)"
  type        = string
}

variable "storage_nodes" {
  description = "Rook-Ceph OSD nodes — one dedicated disk per OVH bare metal server. NEVER include the OS disk."
  type = list(object({
    name    = string
    devices = list(string)
  }))
  default = [
    { name = "bm-01", devices = ["/dev/sdb"] },
    { name = "bm-02", devices = ["/dev/sdb"] },
    { name = "bm-03", devices = ["/dev/sdb"] },
  ]
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificates"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault API address (in-cluster or external)"
  type        = string
  default     = "http://vault.vault.svc.cluster.local:8200"
}

variable "vault_token" {
  description = "Vault authentication token (required for production)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification for Vault (set false in production with proper TLS)"
  type        = bool
  default     = true
}

variable "rgw_s3_endpoint" {
  description = "S3 endpoint reachable from where OpenTofu runs; empty falls back to in-cluster URL"
  type        = string
  default     = ""
}

variable "rgw_s3_access_key" {
  description = "Rook RGW S3 access key for aws.rgw (do not reuse AWS_* — those are OVH state-backend keys)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "rgw_s3_secret_key" {
  description = "Rook RGW S3 secret key for aws.rgw"
  type        = string
  sensitive   = true
  default     = ""
}

variable "vpn_subnet" {
  description = "WireGuard VPN subnet CIDR — used for ingress whitelisting"
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_server_url" {
  description = "WireGuard endpoint hostname or IP (defaults to vpn.<cluster_domain> if empty)"
  type        = string
  default     = ""
}

variable "wireguard_node_port" {
  description = "UDP NodePort for WireGuard (public LB listener port)"
  type        = number
  default     = 31820
}

variable "wireguard_peers" {
  description = "Comma-separated WireGuard peer names (defaults to bootstrap_admin.username)"
  type        = string
  default     = ""
}

variable "wireguard_allowed_ips" {
  description = "Comma-separated AllowedIPs for WireGuard peers (VPN + cluster CIDRs + bare-metal private net)"
  type        = string
  default     = "10.8.0.0/24,10.96.0.0/12,10.244.0.0/16,192.168.0.0/16"
}

variable "keycloak_admin_username" {
  description = "Keycloak master realm admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak master realm admin password"
  type        = string
  sensitive   = true
}

variable "bootstrap_admin" {
  description = "Root platform admin in the maze realm (SSO + VPN). WireGuard peer name matches username."
  type = object({
    username = string
    password = string
    email    = string
  })
  sensitive = true
}

variable "bootstrap_users" {
  description = "Additional Keycloak users created at bootstrap"
  type = list(object({
    username = string
    password = string
    email    = string
    groups   = list(string)
  }))
  sensitive = true
  default   = []
}

# Optional external-PG overrides (unused when apps use in-cluster Bitnami Postgres).
variable "keycloak_postgresql_host" {
  description = "External Keycloak PostgreSQL host (empty = in-cluster)"
  type        = string
  default     = ""
}

variable "keycloak_postgresql_port" {
  description = "External Keycloak PostgreSQL port"
  type        = number
  default     = 0
}

variable "keycloak_postgresql_username" {
  description = "Keycloak PostgreSQL username"
  type        = string
  default     = "keycloak"
}

variable "keycloak_postgresql_database" {
  description = "Keycloak PostgreSQL database name"
  type        = string
  default     = "keycloak"
}

variable "keycloak_postgresql_password" {
  description = "Keycloak PostgreSQL password (in-cluster or external)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "gitlab_postgresql_host" {
  description = "External GitLab PostgreSQL host (empty = in-cluster)"
  type        = string
  default     = ""
}

variable "gitlab_postgresql_port" {
  description = "External GitLab PostgreSQL port"
  type        = number
  default     = 5432
}

variable "gitlab_postgresql_username" {
  description = "GitLab PostgreSQL username"
  type        = string
  default     = "gitlab"
}

variable "gitlab_postgresql_database" {
  description = "GitLab PostgreSQL database name"
  type        = string
  default     = "gitlabhq_production"
}

variable "gitlab_postgresql_password" {
  description = "GitLab PostgreSQL password (in-cluster or external)"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Cluster backup (Velero + Kopia + RGW rclone crypt → OVH Object Storage)
# =============================================================================

variable "backup_enabled" {
  description = "Install Velero, schedule Kopia backups, and mirror RGW buckets to OVH Object Storage. External resources (e.g. managed PostgreSQL) are not covered — the person running the infrastructure must back those up."
  type        = bool
  default     = true
}

variable "backup_s3_bucket" {
  description = "OVH Object Storage bucket name (created by this env when backup_enabled)"
  type        = string
  default     = "maze-cluster-backup-production"
}

variable "backup_s3_prefix" {
  description = "Prefix inside the backup bucket for Velero"
  type        = string
  default     = "velero"
}

variable "backup_s3_region" {
  description = "Deprecated override — prefer ovh_object_storage_region. Empty uses OVH region."
  type        = string
  default     = ""
}

variable "backup_s3_endpoint" {
  description = "Override S3 endpoint (empty = https://s3.<ovh_object_storage_region>.io.cloud.ovh.net)"
  type        = string
  default     = ""
}

variable "backup_s3_access_key" {
  description = "Override OVH S3 access key (empty = use ovh.tf credential)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_s3_secret_key" {
  description = "Override OVH S3 secret key (empty = use ovh.tf credential)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_encryption_password" {
  description = "Shared password for Kopia (Velero) and rclone crypt (RGW mirror). Min 16 chars when backup_enabled. Store offline."
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_schedule_cron" {
  description = "Cron schedule for Velero cluster backups (UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_ttl" {
  description = "Backup retention TTL (Go duration, e.g. 720h = 30d)"
  type        = string
  default     = "720h"
}

variable "backup_object_sync_enabled" {
  description = "Mirror GitLab/Loki RGW buckets to OVH via rclone crypt"
  type        = bool
  default     = true
}

variable "backup_object_sync_schedule_cron" {
  description = "Cron for RGW→OVH object mirror (UTC)"
  type        = string
  default     = "30 2 * * *"
}

variable "backup_postgres_dump_enabled" {
  description = "Schedule logical pg_dump of GitLab/Keycloak Postgres to OVH backup bucket"
  type        = bool
  default     = true
}

variable "backup_postgres_dump_schedule_cron" {
  description = "Cron for logical Postgres dumps (UTC)"
  type        = string
  default     = "0 3 * * *"
}

variable "backup_postgres_dump_prefix" {
  description = "Prefix under the backup bucket for encrypted logical dumps"
  type        = string
  default     = "logical/postgres"
}

# =============================================================================
# OVH Public Cloud (provider + managed Postgres + Object Storage)
# =============================================================================

variable "ovh_endpoint" {
  description = "OVH API endpoint (ovh-eu, ovh-ca, ovh-us). Empty uses OVH_ENDPOINT env."
  type        = string
  default     = "ovh-eu"
}

variable "ovh_application_key" {
  description = "OVH API application key (or OVH_APPLICATION_KEY env)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ovh_application_secret" {
  description = "OVH API application secret (or OVH_APPLICATION_SECRET env)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ovh_consumer_key" {
  description = "OVH API consumer key for cloud/OpenTofu (or OVH_CONSUMER_KEY env). Cloud-project scoped — do not reuse for DNS-01."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ovh_dns_consumer_key" {
  description = "OVH consumer key for cert-manager DNS-01. Must allow /domain/zone/<cluster_domain> only (not the cloud CK)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ovh_cloud_project_id" {
  description = "OVH Public Cloud project ID (service_name)"
  type        = string
}

variable "ovh_private_network_name" {
  description = "Name of the OVH private network (vRack) used by the Public Cloud LB"
  type        = string
  default     = "maze-private-network"
}

variable "ovh_lb_enabled" {
  description = "Manage the OVH Public Cloud Load Balancer (WireGuard UDP only)"
  type        = bool
  default     = true
}

variable "ovh_lb_region" {
  description = "Region of the Public Cloud Load Balancer"
  type        = string
  default     = "UK1"
}

variable "ovh_lb_name" {
  description = "Name of the Public Cloud Load Balancer"
  type        = string
  default     = "maze-public-lb"
}

variable "ovh_lb_flavor_name" {
  description = "LB flavor name (small / medium / large / xl)"
  type        = string
  default     = "small"
}

variable "ovh_lb_floating_ip_id" {
  description = "Existing floating IP UUID to keep on the LB (empty = create new)"
  type        = string
  default     = "140fbf29-8657-4366-a689-86af8ccaea2c"
}

variable "ovh_lb_gateway_id" {
  description = "OVH gateway UUID associated with the LB floating IP"
  type        = string
  default     = "8e1f6f92-7420-41ae-a4b3-aadf28372192"
}

variable "ovh_lb_id" {
  description = "Unused after recreate; kept for docs/inventory of prior LB UUID"
  type        = string
  default     = ""
}

variable "ovh_lb_backend_nodes" {
  description = "Bare-metal private IPs behind the WireGuard UDP listener"
  type = list(object({
    name       = string
    private_ip = string
  }))
  default = [
    { name = "bm-01", private_ip = "192.168.10.1" },
    { name = "bm-02", private_ip = "192.168.10.2" },
    { name = "bm-03", private_ip = "192.168.10.3" },
  ]
}

variable "ovh_postgresql_region" {
  description = "Region for managed PostgreSQL nodes (e.g. UK, GRA)"
  type        = string
  default     = "UK"
}

variable "ovh_postgresql_version" {
  description = "Managed PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "ovh_postgresql_plan" {
  description = "Managed PostgreSQL plan: essential (1 node), business (2), enterprise (3)"
  type        = string
  default     = "essential"

  validation {
    condition     = contains(["essential", "business", "enterprise"], var.ovh_postgresql_plan)
    error_message = "ovh_postgresql_plan must be essential, business, or enterprise."
  }
}

variable "ovh_postgresql_flavor" {
  description = "Managed PostgreSQL node flavor (e.g. db1-4, db1-7)"
  type        = string
  default     = "db1-4"
}

variable "ovh_database_allowed_cidrs" {
  description = "Unused (legacy Public Cloud managed PostgreSQL allowlist). Kept for tfvars compatibility."
  type = list(object({
    description = string
    cidr        = string
  }))
  default = []
}

variable "ovh_object_storage_region" {
  description = "Object Storage region name for primary backups (uppercase in OVH API, e.g. GRA)"
  type        = string
  default     = "GRA"
}

variable "ovh_object_storage_dr_region" {
  description = "Object Storage region for DR replica bucket (uppercase, e.g. SBG)"
  type        = string
  default     = "SBG"
}

variable "tofu_state_s3_bucket" {
  description = "OVH Object Storage bucket name for OpenTofu remote state"
  type        = string
  default     = "maze-opentofu-state-production"
}

variable "backup_s3_dr_bucket" {
  description = "OVH Object Storage DR bucket name (created in ovh_object_storage_dr_region)"
  type        = string
  default     = "maze-cluster-backup-production-sbg"
}

