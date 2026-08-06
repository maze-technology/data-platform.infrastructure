variable "cluster_name" {
  description = "Kubernetes cluster name (must match kubeconfig context naming)"
  type        = string
  default     = "production"
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

variable "wireguard_peers" {
  description = "WireGuard peer names (defaults to bootstrap_admin.username)"
  type        = string
  default     = ""
}

variable "keycloak_postgresql_host" {
  description = "OVH managed PostgreSQL endpoint for Keycloak"
  type        = string
}

variable "keycloak_postgresql_password" {
  description = "OVH managed PostgreSQL password for Keycloak"
  type        = string
  sensitive   = true
}

variable "gitlab_postgresql_host" {
  description = "OVH managed PostgreSQL endpoint for GitLab"
  type        = string
}

variable "gitlab_postgresql_password" {
  description = "OVH managed PostgreSQL password for GitLab"
  type        = string
  sensitive   = true
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
  description = "OVH Object Storage region code (e.g. gra, sbg, de, uk, waw, bhs)"
  type        = string
  default     = "gra"
}

variable "backup_s3_endpoint" {
  description = "OVH S3 endpoint URL"
  type        = string
  default     = "https://s3.gra.io.cloud.ovh.net"
}

variable "backup_s3_access_key" {
  description = "OVH Object Storage S3 access key (required when backup_enabled)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_s3_secret_key" {
  description = "OVH Object Storage S3 secret key (required when backup_enabled)"
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
