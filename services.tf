# Default service catalog (overridable via var.services from the env root).
# Images publish to the GitLab container registry; tags are env-specific.

locals {
  default_services = {
    "assets-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/assets-backend"
      image_tag        = "latest"
      consumer_group   = "assets"
      kafka_topics = [
        "assets.sync.request",
        "assets.fetch.response",
      ]
    }
    "markets-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/markets-backend"
      image_tag        = "latest"
      consumer_group   = "markets"
      kafka_topics = [
        "markets.sync.request",
        "markets.fetch.response",
      ]
    }
    "ohlcvdatasets-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/ohlcvdatasets-backend"
      image_tag        = "latest"
      consumer_group   = "ohlcvdatasets"
      kafka_topics     = []
    }
    "ohlcvs-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/ohlcvs-backend"
      image_tag        = "latest"
      consumer_group   = "ohlcvs"
      kafka_topics     = []
    }
    "exchanges-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/exchanges-backend"
      image_tag        = "latest"
      consumer_group   = "exchanges"
      kafka_topics     = []
    }
    "backtests-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/backtests-backend"
      image_tag        = "latest"
      consumer_group   = "backtests"
      kafka_topics     = []
    }
    "firstratedata-dataprovider-backend" = {
      image_repository = "scm.maze.trading:5050/data-platform/firstratedata-dataprovider-backend"
      image_tag        = "latest"
      consumer_group   = "firstratedata"
      kafka_topics     = []
    }
  }
}
