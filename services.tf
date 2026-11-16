# Default service catalog (overridable via var.services from the env root).
# Images publish to the GitLab container registry; tags are env-specific.

locals {
  default_services = {
    "assets-backend" = {
      image_repository     = "registry.scm.maze.trading/data-platform/assets-backend"
      image_tag            = "latest"
      consumer_group       = "assets"
      ingress_host         = "assets"
      valkey_session_store = true
      # Keep at least one replica for VPN gRPC; KEDA still scales on lag.
      keda_min_replicas = 1
      kafka_topics = [
        "assets.sync.request",
        "assets.sync.response",
        "assets.fetch.request",
        "assets.fetch.response",
      ]
    }
    "markets-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/markets-backend"
      image_tag        = "latest"
      consumer_group   = "markets"
      ingress_host     = "markets"
      kafka_topics = [
        "markets.sync.request",
        "markets.fetch.response",
      ]
    }
    "ohlcvdatasets-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/ohlcvdatasets-backend"
      image_tag        = "latest"
      consumer_group   = "ohlcvdatasets"
      ingress_host     = "ohlcvdatasets"
      kafka_topics     = []
    }
    "ohlcvs-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/ohlcvs-backend"
      image_tag        = "latest"
      consumer_group   = "ohlcvs"
      ingress_host     = "ohlcvs"
      kafka_topics     = []
    }
    "exchanges-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/exchanges-backend"
      image_tag        = "latest"
      consumer_group   = "exchanges"
      ingress_host     = "exchanges"
      kafka_topics     = []
    }
    "backtests-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/backtests-backend"
      image_tag        = "latest"
      consumer_group   = "backtests"
      ingress_host     = "backtests"
      kafka_topics     = []
    }
    "firstratedata-dataprovider-backend" = {
      image_repository = "registry.scm.maze.trading/data-platform/firstratedata-dataprovider-backend"
      image_tag        = "latest"
      consumer_group   = "firstratedata"
      ingress_host     = "firstratedata"
      kafka_topics     = []
    }
  }
}
