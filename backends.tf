# Shared backend chart: one chart, many catalog entries.
# gRPC is exposed VPN-only via ingress-nginx (ClusterIP) + source whitelist.

resource "kubernetes_secret_v1" "registry_pull" {
  count = var.enable_services && var.registry_username != "" && var.registry_password != "" ? 1 : 0

  metadata {
    name      = "data-platform-registry"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-platform"
      environment                 = var.environment
    }
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.registry_server) = {
          username = var.registry_username
          password = var.registry_password
          auth     = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace_v1.data_platform]
}

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
      imagePullSecrets = concat(
        var.image_pull_secrets,
        length(kubernetes_secret_v1.registry_pull) > 0 ? [{ name = kubernetes_secret_v1.registry_pull[0].metadata[0].name }] : [],
      )
      replicaCount = try(each.value.replicas, 1)
      service = {
        grpcPort = 9090
      }
      env = merge(
        {
          KAFKA_BROKERS = coalesce(local.kafka_bootstrap, "localhost:9092")
        },
        var.enable_valkey ? {
          SPRING_DATA_REDIS_HOST     = local.valkey_host
          SPRING_DATA_REDIS_PORT     = "6379"
          SPRING_DATA_REDIS_USERNAME = "default"
        } : {},
        var.enable_valkey && try(each.value.valkey_session_store, false) ? {
          ASSETS_SYNC_SESSION_STORE = "redis"
        } : {},
        var.enable_postgres ? {
          SPRING_DATASOURCE_DEFAULT_URL      = local.postgres_jdbc_url
          SPRING_DATASOURCE_DEFAULT_USERNAME = var.postgres_username
        } : {},
        try(each.value.extra_env, {}),
      )
      envFromSecret = concat(
        var.enable_valkey ? [
          {
            name       = "SPRING_DATA_REDIS_PASSWORD"
            secretName = kubernetes_secret_v1.valkey[0].metadata[0].name
            key        = "default"
          }
        ] : [],
        var.enable_postgres ? [
          {
            name       = "SPRING_DATASOURCE_DEFAULT_PASSWORD"
            secretName = kubernetes_secret_v1.postgres_credentials[0].metadata[0].name
            key        = "password"
          }
        ] : [],
      )
      ingress = {
        enabled   = var.enable_ingress && try(each.value.ingress_enabled, true)
        className = var.ingress_class
        host = format(
          "%s.%s",
          coalesce(try(each.value.ingress_host, null), trimsuffix(each.key, "-backend")),
          var.cluster_domain,
        )
        clusterIssuer        = var.ingress_cluster_issuer
        tlsSecretName        = "${each.key}-tls"
        whitelistSourceRange = var.restrict_to_vpn ? local.ingress_whitelist : ""
      }
      keda = {
        enabled          = var.enable_keda && try(each.value.keda_enabled, true) && local.kafka_bootstrap != null
        pollingInterval  = 30
        cooldownPeriod   = 300
        minReplicaCount  = try(each.value.keda_min_replicas, 0)
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
    kubernetes_manifest.postgres_cluster,
    kubernetes_secret_v1.registry_pull,
  ]
}

locals {
  ingress_whitelist = "${var.vpn_cidr},127.0.0.1/32,10.0.0.0/8"

  # Hostnames for CoreDNS (VPN clients) — same convention as chart ingress.host
  service_ingress_hosts = var.enable_services && var.enable_ingress ? sort([
    for name, svc in local.effective_services : format(
      "%s.%s",
      coalesce(try(svc.ingress_host, null), trimsuffix(name, "-backend")),
      var.cluster_domain,
    )
    if try(svc.ingress_enabled, true)
  ]) : []
}
