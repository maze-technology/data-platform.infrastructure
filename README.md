# data-platform/infrastructure

OpenTofu **module** for the data-platform data plane. Composed from [`iac/infrastructure`](https://scm.maze.trading/iac/infrastructure) env roots (alongside `infrastructure-base`).

## Scope

| Piece | Implementation |
|-------|----------------|
| Namespace | `kubernetes_namespace_v1` |
| KEDA | `helm_release` kedacore/keda (`enable_keda`) |
| Kafka | Strimzi operator + KRaft `Kafka`/`KafkaNodePool` + catalog `KafkaTopic`s (`enable_kafka`) |
| Valkey | valkey-io/valkey chart (`enable_valkey`) — separate from GitLab Valkey |
| Postgres | CloudNativePG `Cluster` (`enable_postgres`) — operator from infrastructure-base |
| Backends | Shared chart `charts/backend` via `helm_release` (`enable_services`) |
| gRPC front | VPN-only nginx Ingress (`enable_ingress`, `restrict_to_vpn`) — **not public** |

## Usage

```hcl
module "data_platform" {
  source = "git::https://scm.maze.trading/data-platform/infrastructure.git?ref=v0.1.0"

  environment      = "production"
  cluster_domain   = "maze.trading"
  vpn_cidr         = "10.8.0.0/24"
  restrict_to_vpn  = true
  enable_keda      = true
  enable_kafka     = true
  enable_valkey    = true
  enable_postgres  = true
  enable_services  = true
  enable_ingress   = true
  kafka_replicas   = 1
  # Narrow the catalog to one service:
  # services = { "assets-backend" = { ... } }
}
```

Pass `ingress_hosts` output into `infrastructure-base` `extra_cluster_dns_hosts` so VPN clients resolve e.g. `assets.maze.trading` → ingress ClusterIP.

Pin a **tag** from env roots (same Renovate style as `infrastructure-base`).

## Layout

```
.
├── charts/backend/   # Deployment, Service (gRPC :9090), VPN Ingress, KEDA ScaledObject
├── keda.tf
├── kafka.tf
├── valkey.tf
├── postgres.tf
├── backends.tf
├── services.tf       # default service catalog
├── main.tf
├── variables.tf
├── outputs.tf
└── versions.tf
```

Service-specific needs belong in catalog/values overrides — not a chart per service.
