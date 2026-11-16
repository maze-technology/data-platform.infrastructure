output "namespace" {
  description = "Kubernetes namespace for data-platform workloads"
  value       = local.namespace
}

output "kafka_enabled" {
  description = "Whether Kafka install is enabled"
  value       = var.enable_kafka
}

output "valkey_enabled" {
  description = "Whether data-platform Valkey install is enabled"
  value       = var.enable_valkey
}

output "keda_enabled" {
  description = "Whether KEDA operator install is enabled"
  value       = var.enable_keda
}

output "services_enabled" {
  description = "Whether backend service workloads are enabled"
  value       = var.enable_services
}

output "service_names" {
  description = "Catalog keys for backend services"
  value       = sort(keys(local.effective_services))
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers (null when Kafka disabled)"
  value       = local.kafka_bootstrap
}

output "valkey_host" {
  description = "Valkey host (null when Valkey disabled)"
  value       = local.valkey_host
}

output "valkey_password" {
  description = "Valkey default ACL user password (null when Valkey disabled)"
  value       = try(random_password.valkey[0].result, null)
  sensitive   = true
}

output "postgres_enabled" {
  description = "Whether CloudNativePG Cluster is enabled"
  value       = var.enable_postgres
}

output "postgres_host" {
  description = "Postgres RW host (null when disabled)"
  value       = local.postgres_host
}

output "postgres_jdbc_url" {
  description = "JDBC URL for the bootstrap database (null when disabled)"
  value       = local.postgres_jdbc_url
}

output "postgres_credentials_secret" {
  description = "Secret name with Postgres username/password"
  value       = try(kubernetes_secret_v1.postgres_credentials[0].metadata[0].name, null)
}

output "ingress_hosts" {
  description = "VPN-only Ingress hostnames for CoreDNS (empty when ingress/services off)"
  value       = local.service_ingress_hosts
}
