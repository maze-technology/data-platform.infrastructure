# Shared backend chart: one chart, many catalog entries.

resource "helm_release" "backend" {
  for_each = var.enable_services ? local.effective_services : {}

  name      = each.key
  chart     = "${path.module}/charts/backend"
  namespace = local.namespace

  wait    = false
  timeout = 300

  values = [
    yamlencode({
      name      = each.key
      namespace = local.namespace
      image = {
        repository = each.value.image_repository
        tag        = each.value.image_tag
        pullPolicy = "IfNotPresent"
      }
      replicaCount = try(each.value.replicas, 1)
      env = merge(
        {
          KAFKA_BROKERS = coalesce(local.kafka_bootstrap, "localhost:9092")
        },
        var.enable_valkey ? {
          VALKEY_HOST = local.valkey_host
          VALKEY_PORT = "6379"
        } : {},
        try(each.value.extra_env, {}),
      )
      keda = {
        enabled          = var.enable_keda && try(each.value.keda_enabled, true) && local.kafka_bootstrap != null
        pollingInterval  = 30
        cooldownPeriod   = 300
        minReplicaCount  = 0
        maxReplicaCount  = 10
        consumerGroup    = coalesce(try(each.value.consumer_group, null), each.key)
        topics           = try(each.value.kafka_topics, [])
        bootstrapServers = coalesce(local.kafka_bootstrap, "")
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.data_platform,
    helm_release.keda,
    kubernetes_manifest.kafka_cluster,
    helm_release.valkey,
  ]
}
