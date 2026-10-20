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

output "services_enabled" {
  description = "Whether backend service workloads are enabled"
  value       = var.enable_services
}

output "service_names" {
  description = "Catalog keys for backend services"
  value       = sort(keys(local.effective_services))
}

# Filled in when Kafka/Valkey helm releases land.
output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers (null until enable_kafka is implemented)"
  value       = null
}

output "valkey_host" {
  description = "Valkey host (null until enable_valkey is implemented)"
  value       = null
}
