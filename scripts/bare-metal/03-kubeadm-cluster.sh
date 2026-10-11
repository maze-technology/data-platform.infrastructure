#!/usr/bin/env bash
# 03-kubeadm-cluster.sh — init first CP, join other CPs+workers, install Cilium
# Usage: ./03-kubeadm-cluster.sh --remote
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
require_ssh_key

WORKDIR="${SCRIPT_DIR}/.cluster-state"
mkdir -p "${WORKDIR}"
chmod 700 "${WORKDIR}"

API_VIP="${API_VIP:-}"
# Prefer dedicated HA VIP when set (kube-vip ARP). Fall back to BM01 private IP.
if [[ -n "${API_VIP}" ]]; then
  CONTROL_PLANE_ENDPOINT="${API_VIP}:6443"
fi
EXTRA_SANS="${API_VIP:+${API_VIP},}${BM01_PRIVATE},${BM02_PRIVATE},${BM03_PRIVATE},${BM01_PUBLIC},${BM02_PUBLIC},${BM03_PUBLIC},${LB_FLOATING_IP},bm-01,bm-02,bm-03,${BM01_SSH},${BM02_SSH},${BM03_SSH}"
CILIUM_API_HOST="${API_VIP:-${BM01_PRIVATE}}"

echo "==> kubeadm init on ${BM01_NAME} (${BM01_SSH}) endpoint=${CONTROL_PLANE_ENDPOINT}"
remote "${BM01_SSH}" "sudo bash -s" <<EOF
set -euo pipefail
# Reset any previous attempt (keep /etc/cni/net.d dir — containerd fatals if removed)
kubeadm reset -f >/dev/null 2>&1 || true
rm -rf /var/lib/cni || true
mkdir -p /etc/cni/net.d /etc/kubernetes/manifests
rm -f /etc/cni/net.d/* || true
systemctl restart containerd
sleep 2
EOF

# HA API VIP: install kube-vip static pod on BM01 before kubeadm init so the VIP exists.
if [[ -n "${API_VIP}" ]]; then
  echo "==> installing kube-vip static pod on first CP (VIP ${API_VIP})"
  "${SCRIPT_DIR}/04-ha-api-vip.sh" --install-first
fi

remote "${BM01_SSH}" "sudo bash -s" <<EOF
set -euo pipefail
kubeadm init \\
  --control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}" \\
  --apiserver-advertise-address="${BM01_PRIVATE}" \\
  --pod-network-cidr="${POD_CIDR}" \\
  --service-cidr="${SERVICE_CIDR}" \\
  --upload-certs \\
  --apiserver-cert-extra-sans="${EXTRA_SANS}"

mkdir -p /home/${SSH_USER}/.kube
cp /etc/kubernetes/admin.conf /home/${SSH_USER}/.kube/config
chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.kube
EOF

echo "==> Fetching join commands + kubeconfig"
JOIN_CP="$(remote "${BM01_SSH}" 'kubeadm token create --print-join-command')"
# certificate key for additional control-planes
CERT_KEY="$(remote "${BM01_SSH}" 'sudo kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1')"
echo "${JOIN_CP}" >"${WORKDIR}/join-worker.sh"
echo "${JOIN_CP} --control-plane --certificate-key ${CERT_KEY}" >"${WORKDIR}/join-control-plane.sh"
chmod 600 "${WORKDIR}/join-"*.sh
remote "${BM01_SSH}" "cat /home/${SSH_USER}/.kube/config" >"${WORKDIR}/admin.conf"
chmod 600 "${WORKDIR}/admin.conf"

# Patch kubeconfig server to use private IP (reachable via SSH tunnel or from nodes)
# Keep as-is (points to CONTROL_PLANE_ENDPOINT host).

join_cp() {
  local host="$1"
  local advertise="$2"
  echo "==> Joining control-plane ${host} (advertise ${advertise})"
  remote "${host}" "sudo bash -s" <<EOF
set -euo pipefail
kubeadm reset -f >/dev/null 2>&1 || true
rm -rf /var/lib/cni || true
mkdir -p /etc/cni/net.d
rm -f /etc/cni/net.d/* || true
systemctl restart containerd
sleep 2
$(cat "${WORKDIR}/join-control-plane.sh") --apiserver-advertise-address=${advertise}
mkdir -p /home/${SSH_USER}/.kube
cp /etc/kubernetes/admin.conf /home/${SSH_USER}/.kube/config
chown -R ${SSH_USER}:${SSH_USER} /home/${SSH_USER}/.kube
EOF
}

join_cp "${BM02_SSH}" "${BM02_PRIVATE}"
join_cp "${BM03_SSH}" "${BM03_PRIVATE}"

# Copy kube-vip static pod to additional CPs (per-node iface).
if [[ -n "${API_VIP}" ]]; then
  echo "==> installing kube-vip on remaining control-planes"
  "${SCRIPT_DIR}/04-ha-api-vip.sh" --install-all
fi

echo "==> Installing Cilium CNI"
remote "${BM01_SSH}" "bash -s" <<EOF
set -euo pipefail
export KUBECONFIG=/home/${SSH_USER}/.kube/config
CILIUM_CLI_VERSION=\$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
CLI_ARCH=amd64
curl -L --fail --remote-name-all \\
  "https://github.com/cilium/cilium-cli/releases/download/\${CILIUM_CLI_VERSION}/cilium-linux-\${CLI_ARCH}.tar.gz"{,.sha256sum}
sha256sum --check "cilium-linux-\${CLI_ARCH}.tar.gz.sha256sum"
sudo tar xzvfC "cilium-linux-\${CLI_ARCH}.tar.gz" /usr/local/bin
rm -f "cilium-linux-\${CLI_ARCH}.tar.gz"{,.sha256sum}

# kube-proxy replacement off initially for simpler first bring-up with kubeadm
# k8sServiceHost must be the HA VIP when API_VIP is set (not a single node IP).
cilium install --version 1.17.2 \\
  --set ipam.mode=kubernetes \\
  --set kubeProxyReplacement=false \\
  --set k8sServiceHost=${CILIUM_API_HOST} \\
  --set k8sServicePort=6443

cilium status --wait
# All three nodes are CP+worker — allow scheduling workloads
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
kubectl get nodes -o wide
kubectl get pods -A
EOF

echo ""
echo "✓ Cluster bootstrapped"
echo "  kubeconfig: ${WORKDIR}/admin.conf"
echo "  API endpoint: ${CONTROL_PLANE_ENDPOINT}"
echo "  From a host without vRack routing, rewrite server to a public CP IP, e.g.:"
echo "    sed -i 's#192.168.10.1:6443#${BM01_PUBLIC}:6443#' ${WORKDIR}/admin.conf"
echo "  Copy kubeconfig:  mkdir -p ~/.kube && cp ${WORKDIR}/admin.conf ~/.kube/config-maze-prod"
echo ""
echo "Next: point production OpenTofu kubeconfig_context at this cluster,"
echo "      set ingress behind OVH LB ${LB_FLOATING_IP}, storage_nodes=/dev/sdb"
