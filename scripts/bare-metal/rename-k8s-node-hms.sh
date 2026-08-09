#!/usr/bin/env bash
# rename-k8s-node-hms.sh — drain/reset/rejoin one kubeadm CP so the Node object
# matches the OS hostname (already set by rename-nodes-hms.sh).
#
# Usage:
#   ./rename-k8s-node-hms.sh <old-k8s-name> <new-k8s-name> <ssh-host> <advertise-ip>
# Example:
#   ./rename-k8s-node-hms.sh bm-03 hms-dreadnought-3623 51.89.153.125 192.168.10.3
#
# Requires: kubectl context with cluster-admin; SSH key from inventory.env
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
require_ssh_key

OLD="${1:?old node name}"
NEW="${2:?new node name}"
SSH_HOST="${3:?ssh host}"
ADVERTISE="${4:?apiserver advertise address}"
KCTX="${KUBECONFIG_CONTEXT:-production}"

echo "==> Preflight: cluster + target"
kubectl --context "${KCTX}" get node "${OLD}" -o wide
HOSTNAME_REMOTE="$(remote "${SSH_HOST}" 'hostname')"
if [[ "${HOSTNAME_REMOTE}" != "${NEW}" ]]; then
  echo "ERROR: remote hostname is '${HOSTNAME_REMOTE}', expected '${NEW}'. Run rename-nodes-hms.sh first." >&2
  exit 1
fi

READY_COUNT="$(kubectl --context "${KCTX}" get nodes --no-headers | awk '$2=="Ready"{c++} END{print c+0}')"
if [[ "${READY_COUNT}" -lt 3 ]]; then
  echo "ERROR: need 3 Ready nodes before renaming (have ${READY_COUNT})" >&2
  exit 1
fi

echo "==> Drain ${OLD}"
kubectl --context "${KCTX}" cordon "${OLD}"
# Background force-deleter for pods stuck Terminating (common when OSD already gone)
(
  for _ in $(seq 1 90); do
    mapfile -t stuck < <(kubectl --context "${KCTX}" get pods -A --field-selector "spec.nodeName=${OLD}" --no-headers 2>/dev/null | awk '$4=="Terminating"{print $1"/"$2}')
    for p in "${stuck[@]:-}"; do
      [[ -z "${p}" ]] && continue
      ns="${p%%/*}"; name="${p#*/}"
      echo "  force-delete ${ns}/${name}"
      kubectl --context "${KCTX}" -n "${ns}" delete pod "${name}" --force --grace-period=0 >/dev/null 2>&1 || true
    done
    sleep 10
  done
) &
FORCE_PID=$!
kubectl --context "${KCTX}" drain "${OLD}" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --grace-period=60 \
  --timeout=20m || true
kill "${FORCE_PID}" 2>/dev/null || true
wait "${FORCE_PID}" 2>/dev/null || true
# Ensure non-DaemonSet pods are gone before reset
left="$(kubectl --context "${KCTX}" get pods -A --field-selector "spec.nodeName=${OLD}" --no-headers 2>/dev/null | awk '$3 !~ /DaemonSet/ && $4!="Completed" {c++} END{print c+0}')"
echo "  remaining non-DS pods on ${OLD}: ${left}"

echo "==> Mint join credentials on a surviving control-plane"
SURVIVOR=""
for n in bm-01 bm-02 bm-03 hms-conqueror-30bd hms-vengeful-4d19 hms-dreadnought-3623; do
  if [[ "${n}" == "${OLD}" ]]; then
    continue
  fi
  if kubectl --context "${KCTX}" get node "${n}" >/dev/null 2>&1; then
    # Map node -> SSH via inventory private/public
    case "${n}" in
      bm-01|hms-conqueror-30bd) SURVIVOR_SSH="${BM01_SSH}" ;;
      bm-02|hms-vengeful-4d19) SURVIVOR_SSH="${BM02_SSH}" ;;
      bm-03|hms-dreadnought-3623) SURVIVOR_SSH="${BM03_SSH}" ;;
      *) continue ;;
    esac
    SURVIVOR="${n}"
    break
  fi
done
if [[ -z "${SURVIVOR}" ]]; then
  echo "ERROR: no surviving control-plane found for join token" >&2
  exit 1
fi
echo "    survivor=${SURVIVOR} ssh=${SURVIVOR_SSH}"

JOIN_BASE="$(remote "${SURVIVOR_SSH}" 'sudo kubeadm token create --print-join-command')"
CERT_KEY="$(remote "${SURVIVOR_SSH}" 'sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1')"
if [[ -z "${JOIN_BASE}" || -z "${CERT_KEY}" ]]; then
  echo "ERROR: failed to create join token/cert key" >&2
  exit 1
fi

echo "==> kubeadm reset on ${SSH_HOST}"
remote "${SSH_HOST}" "sudo bash -s" <<EOF
set -euo pipefail
kubeadm reset -f
rm -rf /var/lib/cni || true
mkdir -p /etc/cni/net.d
rm -f /etc/cni/net.d/* || true
systemctl restart containerd
sleep 2
EOF

echo "==> Delete Node object ${OLD}"
kubectl --context "${KCTX}" delete node "${OLD}" --wait=true

echo "==> Rejoin as ${NEW}"
remote "${SSH_HOST}" "sudo bash -s" <<EOF
set -euo pipefail
${JOIN_BASE} \\
  --control-plane \\
  --certificate-key ${CERT_KEY} \\
  --apiserver-advertise-address=${ADVERTISE} \\
  --node-name=${NEW}
mkdir -p /home/${SSH_USER}/.kube
cp /etc/kubernetes/admin.conf /home/${SSH_USER}/.kube/config
chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.kube
# Allow workloads on CP (same as bootstrap)
kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes ${NEW} node-role.kubernetes.io/control-plane- || true
EOF

echo "==> Wait for Ready"
for i in $(seq 1 60); do
  STATUS="$(kubectl --context "${KCTX}" get node "${NEW}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
  echo "  try ${i}: Ready=${STATUS}"
  [[ "${STATUS}" == "True" ]] && break
  sleep 5
done
kubectl --context "${KCTX}" get nodes -o wide

echo "✓ ${OLD} → ${NEW} complete"
echo "  Next: update storage_nodes in terraform.tfvars to include ${NEW}, then tofu apply Rook."
