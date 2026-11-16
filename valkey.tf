# Data-plane Valkey (separate from GitLab's gitlab-valkey in infrastructure-base).

resource "random_password" "valkey" {
  count = var.enable_valkey ? 1 : 0

  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "valkey" {
  count = var.enable_valkey ? 1 : 0

  metadata {
    name      = "data-platform-valkey"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-platform"
      environment                 = var.environment
    }
  }

  data = {
    # Chart expects ACL user password keys; "default" matches auth.aclUsers.default.
    default = random_password.valkey[0].result
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace_v1.data_platform]
}

resource "helm_release" "valkey" {
  count = var.enable_valkey ? 1 : 0

  name       = local.valkey_release_name
  repository = "https://valkey.io/valkey-helm/"
  chart      = "valkey"
  version    = var.valkey_helm_chart_version
  namespace  = local.namespace

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      auth = {
        enabled = true
        aclUsers = {
          default = {
            permissions = "~* &* +@all"
            passwordKey = "default"
          }
        }
        usersExistingSecret = kubernetes_secret_v1.valkey[0].metadata[0].name
      }
      dataStorage = merge(
        {
          enabled       = true
          requestedSize = var.valkey_storage_size
        },
        var.valkey_storage_class != "" ? { className = var.valkey_storage_class } : {},
      )
      resources = {
        requests = {
          cpu    = "50m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]

  depends_on = [kubernetes_secret_v1.valkey]
}
