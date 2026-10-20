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
  description = "Install Strimzi operator + Kafka cluster"
  type        = bool
  default     = false
}

variable "enable_valkey" {
  description = "Install data-platform Valkey (separate from GitLab Valkey)"
  type        = bool
  default     = false
}

variable "enable_keda" {
  description = "Install KEDA operator (cluster-scoped) for Kafka lag autoscaling"
  type        = bool
  default     = false
}

variable "enable_services" {
  description = "Deploy backend service workloads from the catalog"
  type        = bool
  default     = false
}

variable "keda_namespace" {
  description = "Namespace for the KEDA operator"
  type        = string
  default     = "keda"
}

variable "keda_helm_chart_version" {
  description = "kedacore/keda Helm chart version"
  type        = string
  default     = "2.17.2"
}

variable "strimzi_helm_chart_version" {
  description = "strimzi-kafka-operator Helm chart version"
  type        = string
  default     = "0.45.2"
}

variable "kafka_cluster_name" {
  description = "Strimzi Kafka cluster metadata.name"
  type        = string
  default     = "data-platform"
}

variable "kafka_version" {
  description = "Apache Kafka version for the Strimzi Kafka CR"
  type        = string
  default     = "3.9.0"
}

variable "kafka_metadata_version" {
  description = "Kafka metadataVersion (KRaft)"
  type        = string
  default     = "3.9-IV0"
}

variable "kafka_replicas" {
  description = "Broker/controller replicas in the dual-role node pool (1 for local, 3 for production)"
  type        = number
  default     = 1
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

variable "kafka_topic_partitions" {
  description = "Default partitions for catalog KafkaTopics"
  type        = number
  default     = 3
}

variable "valkey_helm_chart_version" {
  description = "Official valkey-io/valkey-helm chart version (match infrastructure-base GitLab pin when possible)"
  type        = string
  default     = "0.11.0"
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
