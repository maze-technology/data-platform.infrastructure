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
