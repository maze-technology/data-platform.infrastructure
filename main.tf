resource "kubernetes_namespace_v1" "data_platform" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-platform"
      environment                 = var.environment
    }
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace_v1.data_platform[0].metadata[0].name : var.namespace

  # Env roots may pass var.services; otherwise use the in-module catalog.
  # jsondecode → map(object) so the ternary matches var.services' type.
  effective_services = length(var.services) > 0 ? var.services : jsondecode(jsonencode(local.default_services))

  kafka_cluster_name = var.kafka_cluster_name
  kafka_bootstrap = var.enable_kafka ? format(
    "%s-kafka-bootstrap.%s.svc.cluster.local:9092",
    local.kafka_cluster_name,
    local.namespace,
  ) : null

  valkey_release_name = "valkey"
  valkey_host = var.enable_valkey ? format(
    "%s.%s.svc.cluster.local",
    local.valkey_release_name,
    local.namespace,
  ) : null
}
