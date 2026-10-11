# GitLab container security (CE): Trivy scan

For trading algo images in `registry.scm.*`. Works on **GitLab CE** (no EE features).

## Encryption at rest (Gitaly / Ceph)

**PVC / RBD LUKS** (not whole-OSD): only volumes on `rook-ceph-block-encrypted` are encrypted. Bulk OHLCV stays on plain `rook-ceph-block`.

| What | Where |
|------|--------|
| Master passphrase | Vault `secret/ceph/rbd-luks` |
| Same passphrase for CSI | K8s Secret `storage-encryption-secret` in `gitlab` (and `rook-ceph`) |
| Per-volume DEKs | Wrapped in RBD image metadata (unlocked via that passphrase) |
| Gitaly (**production**) | `gitaly_storage_class = rook-ceph-block-encrypted` |
| Gitaly (**local kind**) | `standard` (local-path) — kind mounts `/sys` read-only so kernel RBD (`krbd`) map fails; encryption SC is still created for parity |

**Existing cluster:** enabling encryption does not magically encrypt an already-provisioned Gitaly PVC. Prefer tear down + re-apply (or migrate) so Gitaly is created on the encrypted class from day one.

## Audit events

Skipped on CE (Premium+). Rely on Promtail/Loki container logs for now.

## Scan on build (fail on High+)

### What is a GitLab Runner?

A **worker** that executes CI jobs (build, Trivy). GitLab itself only *schedules* pipelines; without a runner, jobs stay **pending** forever.

We install **one** in-cluster GitLab Runner (`install_gitlab_runner = true`, Kubernetes executor, privileged for Docker builds). Token registration uses the modern `glrt-` auth-token workflow (created via Rails after GitLab is up).

### CI template: Trivy

Template lives in `infrastructure-base` at `ci/templates/container-secure.gitlab-ci.yml` (mirrored here for ops docs).

- `trivy` — fail on High+ (unfixed) and Critical

Example `.gitlab-ci.yml`:

```yaml
stages: [build, secure]

build:
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA

include:
  - project: 'platform/ci-templates'   # after you mirror the template there
    file: '/container-secure.gitlab-ci.yml'
    inputs:
      image: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
      severity: HIGH

variables:
  SECURE_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA
```

Image signing / cluster admission (cosign + Kyverno) was removed; keep the bar simple with Trivy in CI.
