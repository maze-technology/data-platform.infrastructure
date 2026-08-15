output "engineers_group_id" {
  description = "Top-level engineers group ID (null when gitlab_groups_enabled=false)"
  value       = try(gitlab_group.engineers[0].id, null)
}

output "engineers_full_path" {
  description = "Full path of engineers group"
  value       = try(gitlab_group.engineers[0].full_path, null)
}

output "infrastructure_engineers_full_path" {
  description = "Full path engineers/infrastructure-engineers"
  value       = try(gitlab_group.infrastructure_engineers[0].full_path, null)
}

output "release_engineers_full_path" {
  description = "Full path engineers/release-engineers"
  value       = try(gitlab_group.release_engineers[0].full_path, null)
}

output "project_managers_full_path" {
  description = "Full path of project-managers group"
  value       = try(gitlab_group.project_managers[0].full_path, null)
}
