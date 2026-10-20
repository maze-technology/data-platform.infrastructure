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
  effective_services = length(var.services) > 0 ? var.services : local.default_services
}

# --- Kafka (Strimzi) ----------------------------------------------------------
# enable_kafka gates install. Chart/version pins land in a follow-up MR.

resource "terraform_data" "kafka_placeholder" {
  count = var.enable_kafka ? 1 : 0

  input = {
    namespace = local.namespace
    note      = "TODO: helm_release strimzi-operator + Kafka CR"
  }
}

# --- Valkey (data-plane cache; not GitLab's valkey) ----------------------------

resource "terraform_data" "valkey_placeholder" {
  count = var.enable_valkey ? 1 : 0

  input = {
    namespace   = local.namespace
    storage     = var.valkey_storage_size
    storage_cls = var.valkey_storage_class
    note        = "TODO: helm_release valkey-io/valkey"
  }
}

# --- Backend services (shared chart + catalog) --------------------------------

resource "terraform_data" "services_placeholder" {
  for_each = var.enable_services ? local.effective_services : {}

  input = {
    namespace = local.namespace
    name      = each.key
    image     = "${each.value.image_repository}:${each.value.image_tag}"
    note      = "TODO: helm_release shared backend chart + KEDA ScaledObject"
  }
}
