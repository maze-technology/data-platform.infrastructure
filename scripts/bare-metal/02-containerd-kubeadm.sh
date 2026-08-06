#!/usr/bin/env bash
# 02-containerd-kubeadm.sh — container runtime + kubeadm/kubelet/kubectl
# Usage: ./02-containerd-kubeadm.sh --remote
#    or: sudo ./02-containerd-kubeadm.sh   (on node)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

INSTALL_BODY="$(cat <<'EOS'
set -euo pipefail
K8S_VERSION="${1:?k8s minor version e.g. 1.32}"
export DEBIAN_FRONTEND=noninteractive

echo "==> Installing containerd"
apt-get update -y
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
# systemd cgroup driver (required by kubeadm)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd

echo "==> Kubernetes apt repo (v${K8S_VERSION})"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 0644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  >/etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet

echo "==> Versions"
containerd --version
kubeadm version -o short
kubelet --version
kubectl version --client -o yaml | head -20

echo "==> containerd + kubeadm ready on $(hostname)"
EOS
)"

if [[ "${1:-}" == "--remote" ]]; then
  require_ssh_key
  for host in "${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}"; do
    echo "======== ${host} ========"
    remote "${host}" "sudo bash -s -- ${K8S_VERSION}" <<<"${INSTALL_BODY}"
  done
  echo "✓ containerd + kubeadm installed on all nodes"
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on the node, or use --remote" >&2
  exit 1
fi

bash -c "${INSTALL_BODY}" -- "${K8S_VERSION}"
