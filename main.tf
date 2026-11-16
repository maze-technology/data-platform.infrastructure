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
  # A `for` expression yields map(...) so the ternary matches var.services.
  default_services_map = {
    for name, svc in local.default_services : name => {
      image_repository     = svc.image_repository
      image_tag            = try(svc.image_tag, "latest")
      replicas             = try(svc.replicas, 1)
      keda_enabled         = try(svc.keda_enabled, true)
      keda_min_replicas    = try(svc.keda_min_replicas, 0)
      consumer_group       = try(svc.consumer_group, null)
      kafka_topics         = try(svc.kafka_topics, [])
      ingress_enabled      = try(svc.ingress_enabled, true)
      ingress_host         = try(svc.ingress_host, null)
      valkey_session_store = try(svc.valkey_session_store, false)
      extra_env            = try(svc.extra_env, {})
    }
  }
  effective_services = length(var.services) > 0 ? var.services : local.default_services_map

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
