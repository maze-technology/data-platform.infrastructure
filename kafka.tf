# Strimzi operator + Kafka cluster (KRaft dual-role node pool).

resource "helm_release" "strimzi" {
  count = var.enable_kafka ? 1 : 0

  name       = "strimzi-kafka-operator"
  repository = "https://strimzi.io/charts/"
  chart      = "strimzi-kafka-operator"
  version    = var.strimzi_helm_chart_version
  namespace  = local.namespace

  wait          = true
  wait_for_jobs = true
  timeout       = 600

  values = [
    yamlencode({
      watchAnyNamespace = false
      watchNamespaces   = [local.namespace]
      resources = {
        requests = {
          memory = "384Mi"
          cpu    = "100m"
        }
        limits = {
          memory = "768Mi"
          cpu    = "1000m"
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace_v1.data_platform]
}

# CRDs are registered asynchronously after the operator deploy.
resource "time_sleep" "wait_strimzi_crds" {
  count = var.enable_kafka ? 1 : 0

  create_duration = "45s"

  depends_on = [helm_release.strimzi]
}

resource "kubernetes_manifest" "kafka_node_pool" {
  count = var.enable_kafka ? 1 : 0

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaNodePool"
    metadata = {
      name      = "dual-role"
      namespace = local.namespace
      labels = {
        "strimzi.io/cluster" = local.kafka_cluster_name
      }
    }
    spec = {
      replicas = var.kafka_replicas
      roles    = ["controller", "broker"]
      storage = {
        type = "jbod"
        volumes = [
          merge(
            {
              id          = 0
              type        = "persistent-claim"
              size        = var.kafka_storage_size
              deleteClaim = false
            },
            var.kafka_storage_class != "" ? { class = var.kafka_storage_class } : {},
          )
        ]
      }
    }
  }

  depends_on = [time_sleep.wait_strimzi_crds]
}

resource "kubernetes_manifest" "kafka_cluster" {
  count = var.enable_kafka ? 1 : 0

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "Kafka"
    metadata = {
      name      = local.kafka_cluster_name
      namespace = local.namespace
      annotations = {
        "strimzi.io/node-pools" = "enabled"
        "strimzi.io/kraft"      = "enabled"
      }
    }
    spec = {
      kafka = {
        version         = var.kafka_version
        metadataVersion = var.kafka_metadata_version
        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          }
        ]
        config = {
          "offsets.topic.replication.factor"         = min(var.kafka_replicas, 3)
          "transaction.state.log.replication.factor" = min(var.kafka_replicas, 3)
          "transaction.state.log.min.isr"            = min(var.kafka_replicas, 2) < 2 ? 1 : 2
          "default.replication.factor"               = min(var.kafka_replicas, 3)
          "min.insync.replicas"                      = min(var.kafka_replicas, 2) < 2 ? 1 : 2
        }
      }
      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [
    time_sleep.wait_strimzi_crds,
    kubernetes_manifest.kafka_node_pool,
  ]
}

# Create catalog topics (best-effort; Strimzi Topic Operator).
resource "kubernetes_manifest" "kafka_topic" {
  for_each = var.enable_kafka ? local.kafka_topics : toset([])

  manifest = {
    apiVersion = "kafka.strimzi.io/v1beta2"
    kind       = "KafkaTopic"
    metadata = {
      name      = replace(each.value, ".", "-")
      namespace = local.namespace
      labels = {
        "strimzi.io/cluster" = local.kafka_cluster_name
      }
    }
    spec = {
      topicName  = each.value
      partitions = var.kafka_topic_partitions
      replicas   = min(var.kafka_replicas, 3)
      config = {
        "retention.ms" = "604800000"
      }
    }
  }

  depends_on = [kubernetes_manifest.kafka_cluster]
}

locals {
  kafka_topics = toset(flatten([
    for svc in values(local.effective_services) : try(svc.kafka_topics, [])
  ]))
}
