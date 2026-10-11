#!/usr/bin/env bash
# 04-ha-api-vip.sh — kube-vip ARP VIP for the Kubernetes API (HA control-plane endpoint)
#
# Inventory:
#   API_VIP=192.168.10.10
#   CONTROL_PLANE_ENDPOINT=${API_VIP}:6443
#
# Existing cluster (API must already be reachable):
#   ./04-ha-api-vip.sh --migrate
#
# Greenfield: set API_VIP + CONTROL_PLANE_ENDPOINT in inventory; 03-kubeadm-cluster.sh
# installs kube-vip before kubeadm init.
#
# Break-glass: OVH IPMI/KVM (no out-of-band VPN required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"
require_ssh_key

MIGRATE=0
MODE=""
for arg in "$@"; do
  case "${arg}" in
    --migrate) MIGRATE=1 ;;
    --install-all) MODE=install-all ;;
    --install-first) MODE=install-first ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
  esac
done

API_VIP="${API_VIP:-192.168.10.10}"
KVVERSION="${KUBE_VIP_VERSION:-v0.8.10}"
CP_EP="${API_VIP}:6443"

detect_vrack_iface() {
  local host="$1"
  remote "${host}" "ip -o -4 addr show | awk '\$4 ~ /^192\\.168\\.10\\./ {print \$2; exit}' | sed 's/@.*//'"
}

# Install kube-vip static pod on one CP (per-node iface; control-plane ARP only).
install_kube_vip_on() {
  local host="$1"
  local iface
  iface="$(detect_vrack_iface "${host}")"
  if [[ -z "${iface}" ]]; then
    echo "ERROR: no 192.168.10.x iface on ${host}" >&2
    exit 1
  fi
  echo "==> kube-vip on ${host} iface=${iface} vip=${API_VIP}"
  remote "${host}" "sudo bash -s" <<EOF
set -euo pipefail
KVVERSION='${KVVERSION}'
VIP='${API_VIP}'
IFACE='${iface}'
ctr image pull "ghcr.io/kube-vip/kube-vip:\${KVVERSION}"
ctr run --rm --net-host "ghcr.io/kube-vip/kube-vip:\${KVVERSION}" kube-vip-gen \\
  /kube-vip manifest pod \\
    --interface "\${IFACE}" \\
    --address "\${VIP}" \\
    --controlplane \\
    --arp \\
    --leaderElection \\
  | tee /etc/kubernetes/manifests/kube-vip.yaml >/dev/null
# kubeadm >=1.29: admin.conf may be unusable at first boot; prefer it when present.
if [[ ! -s /etc/kubernetes/admin.conf ]] && [[ -f /etc/kubernetes/super-admin.conf ]]; then
  sed -i 's#/etc/kubernetes/admin.conf#/etc/kubernetes/super-admin.conf#' \\
    /etc/kubernetes/manifests/kube-vip.yaml
fi
EOF
}

install_all_cps() {
  local h
  for h in "${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}"; do
    install_kube_vip_on "${h}"
  done
}

# Greenfield helper: install on BM01 only (before kubeadm init); join copies later.
install_first_cp() {
  install_kube_vip_on "${BM01_SSH}"
}

retarget_file_to_vip() {
  local host="$1"
  remote "${host}" "sudo bash -s" <<EOF
set -euo pipefail
EP='${CP_EP}'
for f in \\
  /etc/kubernetes/admin.conf \\
  /etc/kubernetes/kubelet.conf \\
  /etc/kubernetes/controller-manager.conf \\
  /etc/kubernetes/scheduler.conf \\
  /home/${SSH_USER}/.kube/config
do
  [[ -f "\$f" ]] || continue
  sed -i -E "s#server: https://192\\.168\\.10\\.[0-9]+:6443#server: https://\${EP}#g" "\$f"
done
EOF
}

renew_apiserver_sans_on() {
  local host="$1"
  local advertise="$2"
  local sans="${API_VIP},${BM01_PRIVATE},${BM02_PRIVATE},${BM03_PRIVATE},${BM01_PUBLIC},${BM02_PUBLIC},${BM03_PUBLIC}"
  remote "${host}" "sudo bash -s" <<EOF
set -euo pipefail
SANS='${sans}'
ADV='${advertise}'
# Backup then regenerate apiserver cert with VIP in SANs
cp -a /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.crt.bak.\$(date +%s) || true
cp -a /etc/kubernetes/pki/apiserver.key /etc/kubernetes/pki/apiserver.key.bak.\$(date +%s) || true
rm -f /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
kubeadm init phase certs apiserver \\
  --apiserver-advertise-address="\${ADV}" \\
  --apiserver-cert-extra-sans="\${SANS}" \\
  --service-cidr="${SERVICE_CIDR}"
# Bounce static pod
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml
sleep 6
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
}

patch_kubeadm_configmap() {
  export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-maze-prod}"
  local tmp
  tmp="$(mktemp)"
  kubectl -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' >"${tmp}"
  python3 - "${tmp}" "${CP_EP}" "${API_VIP}" <<'PY'
import sys, re
path, endpoint, vip = sys.argv[1:4]
text = open(path).read()
if re.search(r"(?m)^controlPlaneEndpoint:", text):
    text = re.sub(r"(?m)^controlPlaneEndpoint:.*$", f"controlPlaneEndpoint: {endpoint}", text)
else:
    text = text.rstrip() + f"\ncontrolPlaneEndpoint: {endpoint}\n"
if "certSANs:" in text:
    if vip not in text:
        text = text.replace("certSANs:", f"certSANs:\n  - {vip}", 1)
else:
    if re.search(r"(?m)^apiServer:", text):
        text = re.sub(
            r"(?m)^apiServer:\n",
            f"apiServer:\n  certSANs:\n  - {vip}\n",
            text,
            count=1,
        )
open(path, "w").write(text)
PY
  kubectl -n kube-system create configmap kubeadm-config \
    --from-file=ClusterConfiguration="${tmp}" \
    -o yaml --dry-run=client | kubectl apply -f -
  rm -f "${tmp}"
}

migrate_existing() {
  export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-maze-prod}"
  echo "==> migrate control-plane endpoint → ${CP_EP} (KUBECONFIG=${KUBECONFIG})"
  if ! kubectl get --raw=/readyz >/dev/null 2>&1; then
    echo "ERROR: API not reachable. Recover the cluster first, then re-run --migrate." >&2
    exit 1
  fi

  install_all_cps
  echo "==> waiting for VIP ${API_VIP} (ARP)..."
  local i
  for i in $(seq 1 45); do
    if ping -c1 -W1 "${API_VIP}" >/dev/null 2>&1; then
      echo "VIP is reachable"
      break
    fi
    sleep 2
  done

  patch_kubeadm_configmap
  renew_apiserver_sans_on "${BM01_SSH}" "${BM01_PRIVATE}"
  renew_apiserver_sans_on "${BM02_SSH}" "${BM02_PRIVATE}"
  renew_apiserver_sans_on "${BM03_SSH}" "${BM03_PRIVATE}"

  echo "==> waiting for apiservers after cert renew..."
  sleep 20
  for h in "${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}"; do
    retarget_file_to_vip "${h}"
    remote "${h}" "sudo systemctl restart kubelet" || true
  done

  if kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
    echo "==> pointing Cilium KUBERNETES_SERVICE_HOST at VIP"
    # Helm/Cilium injects the API host as a container env (not always in cilium-config).
    kubectl -n kube-system set env ds/cilium "KUBERNETES_SERVICE_HOST=${API_VIP}" || true
    if kubectl -n kube-system get deploy cilium-operator >/dev/null 2>&1; then
      kubectl -n kube-system set env deploy/cilium-operator "KUBERNETES_SERVICE_HOST=${API_VIP}" || true
    fi
    if kubectl -n kube-system get cm cilium-config >/dev/null 2>&1; then
      kubectl -n kube-system patch cm cilium-config --type merge \
        -p "{\"data\":{\"k8s-service-host\":\"${API_VIP}\",\"k8s-service-port\":\"6443\"}}" || true
    fi
  fi

  echo "==> verify"
  sleep 10
  kubectl get nodes -o wide || true
  echo -n "VIP readyz: "
  curl -sk --max-time 5 "https://${API_VIP}:6443/readyz" || echo "(unreachable from this host — update VPN/kubeconfig)"
  echo ""
  echo "Next:"
  echo "  1. inventory.env: API_VIP=${API_VIP}  CONTROL_PLANE_ENDPOINT=${CP_EP}"
  echo "  2. laptop kubeconfig server: https://${CP_EP}"
  echo "  3. Break-glass remains OVH IPMI/KVM (not an external VPN box)."
}

if [[ "${MIGRATE}" -eq 1 ]]; then
  migrate_existing
elif [[ "${MODE}" == "install-all" ]]; then
  install_all_cps
elif [[ "${MODE}" == "install-first" ]]; then
  install_first_cp
else
  cat <<EOF
Usage:
  ./04-ha-api-vip.sh --migrate       # existing cluster → HA VIP
  ./04-ha-api-vip.sh --install-all   # static pods on all CPs only
  ./04-ha-api-vip.sh --install-first # BM01 only (greenfield pre-init)

Set API_VIP (default ${API_VIP}) and CONTROL_PLANE_ENDPOINT=${CP_EP} in inventory.env.
EOF
fi
