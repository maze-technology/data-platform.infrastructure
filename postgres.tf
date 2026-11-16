# CloudNativePG Cluster for data-platform backends (operator already cluster-scoped via infrastructure-base).

resource "random_password" "postgres" {
  count = var.enable_postgres ? 1 : 0

  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "postgres_credentials" {
  count = var.enable_postgres ? 1 : 0

  metadata {
    name      = "${local.postgres_cluster_name}-credentials"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-platform"
      environment                 = var.environment
      "cnpg-cluster"              = local.postgres_cluster_name
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = var.postgres_username
    password = random_password.postgres[0].result
  }

  depends_on = [kubernetes_namespace_v1.data_platform]
}

resource "kubernetes_manifest" "postgres_cluster" {
  count = var.enable_postgres ? 1 : 0

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"
    metadata = {
      name      = local.postgres_cluster_name
      namespace = local.namespace
      labels = {
        "app.kubernetes.io/part-of" = "data-platform"
        environment                 = var.environment
        "cnpg-cluster"              = local.postgres_cluster_name
      }
    }
    spec = {
      instances = var.postgres_instances
      storage = merge(
        {
          size = var.postgres_storage_size
        },
        var.postgres_storage_class != "" ? { storageClass = var.postgres_storage_class } : {},
      )
      bootstrap = {
        initdb = {
          database = var.postgres_database
          owner    = var.postgres_username
          secret = {
            name = kubernetes_secret_v1.postgres_credentials[0].metadata[0].name
          }
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [kubernetes_secret_v1.postgres_credentials]
}

locals {
  postgres_cluster_name = "data-platform-pg"
  postgres_host = var.enable_postgres ? format(
    "%s-rw.%s.svc.cluster.local",
    local.postgres_cluster_name,
    local.namespace,
  ) : null
  postgres_jdbc_url = var.enable_postgres ? format(
    "jdbc:postgresql://%s:5432/%s",
    local.postgres_host,
    var.postgres_database,
  ) : null
}
