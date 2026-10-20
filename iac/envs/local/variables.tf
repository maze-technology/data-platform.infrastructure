variable "cluster_domain" {
  description = "Base domain for all cluster services (e.g. maze.local). Add entries to /etc/hosts pointing to your VPS IP."
  type        = string
  default     = "maze.local"
}

variable "cluster_public_ip" {
  description = "Public IP of the VPS/bare-metal host — used in /etc/hosts output helper. Leave empty to omit from output."
  type        = string
  default     = ""
}

variable "keycloak_admin_username" {
  description = "Keycloak master realm admin username (bootstrap — access /admin console to manage users)"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak master realm admin password"
  type        = string
  sensitive   = true
  default     = "ChangeMe-Keycloak-Admin-123!"
}

variable "bootstrap_admin" {
  description = "Root platform admin in the maze realm (SSO login + VPN access). WireGuard peer name matches username."
  type = object({
    username = string
    password = string
    email    = string
  })
  sensitive = true
  default = {
    username = "admin"
    password = "ChangeMe-Platform-Admin-123!"
    email    = "admin@maze.tech"
  }
}

variable "bootstrap_users" {
  description = "Additional users created in Keycloak at bootstrap (optional)"
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
  description = "WireGuard peer names for bootstrap VPN access. Defaults to bootstrap_admin.username. Must match Keycloak usernames in vpn-users group."
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig for the target cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubectl context for the target cluster"
  type        = string
  default     = "kind-local"
}

variable "vault_address" {
  description = "Vault API URL reachable from where OpenTofu runs (port-forward, VPN, or ingress)"
  type        = string
  default     = ""
}

variable "vault_token" {
  description = "Vault token for OpenTofu (local kind bootstrap default)"
  type        = string
  sensitive   = true
  default     = "root"
}

variable "vault_skip_tls_verify" {
  description = "Skip TLS verification for Vault"
  type        = bool
  default     = true
}

variable "rgw_s3_endpoint" {
  description = "S3 endpoint reachable from where OpenTofu runs; empty falls back to in-cluster URL"
  type        = string
  default     = ""
}

# =============================================================================
# Cluster backup (Velero + Kopia → local RGW bucket for smoke tests)
# =============================================================================

variable "backup_enabled" {
  description = "Install Velero and schedule encrypted Kopia backups to a local RGW bucket"
  type        = bool
  default     = true
}

variable "backup_s3_bucket" {
  description = "RGW bucket name for Velero backups (created by this env)"
  type        = string
  default     = "cluster-backup-local"
}

variable "backup_s3_prefix" {
  description = "Prefix inside the backup bucket"
  type        = string
  default     = "velero"
}

variable "backup_s3_access_key" {
  description = "RGW access key for Velero (Makefile sets from Vault during apply-services)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_s3_secret_key" {
  description = "RGW secret key for Velero (Makefile sets from Vault during apply-services)"
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
  description = "Cron schedule for cluster backups (UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "backup_ttl" {
  description = "Backup retention TTL (Go duration, e.g. 168h = 7d)"
  type        = string
  default     = "168h"
}

variable "backup_object_sync_enabled" {
  description = "Mirror GitLab/Loki RGW buckets into the backup store via rclone crypt"
  type        = bool
  default     = true
}

variable "backup_object_sync_schedule_cron" {
  description = "Cron for RGW object mirror (UTC)"
  type        = string
  default     = "30 2 * * *"
}

variable "enable_data_platform" {
  description = "Compose data-platform/infrastructure (Kafka, Valkey, backends). Off until first tagged module release is ready."
  type        = bool
  default     = false
}
