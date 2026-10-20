variable "environment" {
  description = "Environment name (local, production, …)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for data-platform workloads"
  type        = string
  default     = "data-platform"
}

variable "create_namespace" {
  description = "Create the data-platform namespace"
  type        = bool
  default     = true
}

variable "enable_kafka" {
  description = "Install Strimzi operator + Kafka cluster (placeholder until chart pins land)"
  type        = bool
  default     = false
}

variable "enable_valkey" {
  description = "Install data-platform Valkey (separate from GitLab Valkey)"
  type        = bool
  default     = false
}

variable "enable_services" {
  description = "Deploy backend service workloads from the catalog"
  type        = bool
  default     = false
}

variable "valkey_storage_size" {
  description = "PVC size for data-platform Valkey"
  type        = string
  default     = "8Gi"
}

variable "valkey_storage_class" {
  description = "StorageClass for Valkey PVC (empty = cluster default)"
  type        = string
  default     = ""
}

variable "kafka_storage_size" {
  description = "Per-broker PVC size for Kafka"
  type        = string
  default     = "20Gi"
}

variable "kafka_storage_class" {
  description = "StorageClass for Kafka PVCs (empty = cluster default)"
  type        = string
  default     = ""
}

variable "services" {
  description = <<-EOT
    Backend service catalog. Each entry is rendered by the shared backend chart
    (when enable_services is true). Specific needs go in values overrides, not
    a separate chart per service.
  EOT
  type = map(object({
    image_repository = string
    image_tag        = optional(string, "latest")
    replicas         = optional(number, 1)
    keda_enabled     = optional(bool, true)
    consumer_group   = optional(string)
    kafka_topics     = optional(list(string), [])
    extra_env        = optional(map(string), {})
  }))
  default = {}
}
