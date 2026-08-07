output "cluster_domain" {
  description = "Base domain for cluster services"
  value       = module.infrastructure_base.cluster_domain
}

output "service_urls" {
  description = "Service URLs (VPN-gated; Let's Encrypt TLS)"
  value       = module.infrastructure_base.service_urls
}

output "wireguard_peer_config_command" {
  description = "Retrieve WireGuard config for bootstrap admin (run on a machine with kubectl access)"
  value       = module.infrastructure_base.wireguard_peer_config_command
}

output "cosign_vault_path" {
  description = "Vault path for cosign signing keys (private_key, public_key, password)"
  value       = module.infrastructure_base.cosign_vault_path
}

output "cosign_ci_scope" {
  description = "COSIGN_* CI variables are instance-level (available to all projects)"
  value       = module.infrastructure_base.cosign_ci_scope
}

output "gitlab_org_group" {
  description = "GitLab org group shared with engineers"
  value       = module.infrastructure_base.gitlab_org_group
}

output "kyverno_signed_images_label" {
  description = "Label namespaces with this to require cosign-verified images from the Maze registry"
  value       = module.infrastructure_base.kyverno_signed_images_label
}

output "bootstrap_credentials" {
  description = "Initial credentials — day-to-day login is Keycloak SSO; Keycloak master is break-glass only"
  sensitive   = true
  value       = module.infrastructure_base.bootstrap_credentials
}

output "storage_class_name" {
  description = "Rook-Ceph RBD StorageClass (unencrypted)"
  value       = module.infrastructure_base.storage_class_name
}

output "encrypted_storage_class_name" {
  description = "Rook-Ceph encrypted RBD StorageClass"
  value       = module.infrastructure_base.encrypted_storage_class_name
}

output "rgw_endpoint" {
  description = "In-cluster S3 endpoint for Rook-Ceph RGW"
  value       = module.infrastructure_base.rgw_endpoint
}

output "gitlab_url" {
  description = "GitLab web UI URL"
  value       = module.infrastructure_base.gitlab_url
}

output "registry_url" {
  description = "GitLab Container Registry URL"
  value       = module.infrastructure_base.registry_url
}

output "backup_schedule" {
  description = "Velero schedule when backups are enabled (OVH Object Storage)"
  sensitive   = true
  value       = module.infrastructure_base.backup_schedule
}

output "ovh_backup_bucket" {
  description = "OVH Object Storage primary bucket for cluster backups (GRA)"
  value       = local.backup_s3_bucket
}

output "ovh_backup_dr_bucket" {
  description = "OVH Object Storage DR bucket (SBG), fed by async replication from GRA"
  value       = local.backup_s3_dr_bucket
}

output "ovh_backup_dr_endpoint" {
  description = "S3 endpoint for the DR backup bucket"
  value       = local.backup_s3_dr_endpoint
}

