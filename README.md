# data-platform/infrastructure

OpenTofu **module** for the data-platform data plane. Composed from [`iac/infrastructure`](https://scm.maze.trading/iac/infrastructure) env roots (alongside `infrastructure-base`).

## Scope

| Piece | Implementation |
|-------|----------------|
| Namespace | `kubernetes_namespace_v1` |
| KEDA | `helm_release` kedacore/keda (`enable_keda`) |
| Kafka | Strimzi operator + KRaft `Kafka`/`KafkaNodePool` + catalog `KafkaTopic`s (`enable_kafka`) |
| Valkey | valkey-io/valkey chart (`enable_valkey`) — separate from GitLab Valkey |
| Backends | Shared chart `charts/backend` via `helm_release` (`enable_services`) |

## Usage

```hcl
module "data_platform" {
  source = "git::https://scm.maze.trading/data-platform/infrastructure.git?ref=v0.1.0"

  environment      = "local"
  enable_keda      = true
  enable_kafka     = true
  enable_valkey    = true
  enable_services  = true
  kafka_replicas   = 1
  # production: kafka_replicas = 3
}
```

Pin a **tag** from env roots (same Renovate style as `infrastructure-base`).

## Layout

```
.
├── charts/backend/   # shared Spring Boot chart + optional KEDA ScaledObject
├── keda.tf
├── kafka.tf
├── valkey.tf
├── backends.tf
├── services.tf       # default service catalog
├── main.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```

Service-specific needs belong in catalog/values overrides — not a chart per service.
