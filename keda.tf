# KEDA operator (cluster-scoped). ScaledObjects live next to each backend chart.

resource "kubernetes_namespace_v1" "keda" {
  count = var.enable_keda ? 1 : 0

  metadata {
    name = var.keda_namespace
    labels = {
      "app.kubernetes.io/part-of" = "data-platform"
      environment                 = var.environment
    }
  }
}

resource "helm_release" "keda" {
  count = var.enable_keda ? 1 : 0

  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_helm_chart_version
  namespace  = kubernetes_namespace_v1.keda[0].metadata[0].name

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      # Keep defaults; CRDs ship with the chart.
    })
  ]
}
