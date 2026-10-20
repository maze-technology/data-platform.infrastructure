# data-platform/infrastructure

OpenTofu **module** for the data-platform data plane. Composed from [`iac/infrastructure`](https://scm.maze.trading/iac/infrastructure) env roots (alongside `infrastructure-base`).

## Scope

| Piece | Status |
|-------|--------|
| Namespace | Implemented |
| Kafka (Strimzi) | Gated (`enable_kafka`); chart pin TBD |
| Valkey (data-plane) | Gated (`enable_valkey`); separate from GitLab Valkey |
| Backend workloads | Gated (`enable_services`); shared Helm chart under `charts/backend` |
| KEDA ScaledObjects | Template in shared chart (operator stays on the platform) |

## Usage

```hcl
module "data_platform" {
  source = "git::https://scm.maze.trading/data-platform/infrastructure.git?ref=v0.1.0"

  environment = "local"
  # enable_kafka    = true
  # enable_valkey   = true
  # enable_services = true
  # services        = merge(module.data_platform./* or pass catalog */)
}
```

Pin a **tag** from env roots (same Renovate style as `infrastructure-base`).

## Layout

```
.
├── charts/backend/   # shared Spring Boot chart + optional KEDA ScaledObject
├── main.tf           # namespace + gated placeholders
├── services.tf       # default service catalog
├── variables.tf
├── outputs.tf
└── versions.tf
```

Service-specific needs belong in catalog/values overrides — not a chart per service.
