output "cluster_domain" {
  description = "Base domain for cluster services"
  value       = module.infrastructure_base.cluster_domain
}

output "service_urls" {
  description = "Service URLs (VPN + /etc/hosts → ClusterIPs; trust Maze CA or accept browser warning)"
  value       = module.infrastructure_base.service_urls
}

output "maze_ca_install_hint" {
  description = "How to export the Maze CA for trusting local HTTPS (optional)"
  value       = module.infrastructure_base.maze_ca_install_hint
}

output "etc_hosts" {
  description = "Lines to add to /etc/hosts — replace VPS_IP with your server public IP"
  value       = module.infrastructure_base.etc_hosts
}

output "wireguard_peer_config_command" {
  description = "Retrieve WireGuard config for bootstrap admin (run on machine with kubectl access)"
  value       = module.infrastructure_base.wireguard_peer_config_command
}

output "bootstrap_credentials" {
  description = "Initial credentials — day-to-day login is Keycloak SSO; Keycloak master + Vault token are break-glass only"
  sensitive   = true
  value       = module.infrastructure_base.bootstrap_credentials
}

output "backup_schedule" {
  description = "Velero schedule when backups are enabled (local RGW smoke target)"
  sensitive   = true
  value       = module.infrastructure_base.backup_schedule
}

output "data_platform_namespace" {
  description = "Data-platform namespace when enable_data_platform is true"
  value       = try(module.data_platform[0].namespace, null)
}
