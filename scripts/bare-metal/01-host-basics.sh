#!/usr/bin/env bash
# 01-host-basics.sh — OS prep on a single node (run via run-all or locally with sudo).
# Usage (on node): sudo ./01-host-basics.sh <hostname> <private_ip> <hosts_block_b64> [vrack_cidr] [vpn_cidr] [pod_cidr]
# Usage (from laptop): ./01-host-basics.sh --remote
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

HOST_BASICS_BODY="$(cat <<'EOS'
set -euo pipefail
HOSTNAME_FQDN="${1:?hostname required}"
PRIVATE_IP="${2:?private ip required}"
HOSTS_BLOCK="$(printf '%s' "${3:?hosts block b64}" | base64 -d)"
VRACK_CIDR="${4:-192.168.0.0/16}"
VPN_CIDR="${5:-10.8.0.0/24}"
POD_CIDR="${6:-10.244.0.0/16}"

export DEBIAN_FRONTEND=noninteractive

echo "==> Setting hostname to ${HOSTNAME_FQDN}"
hostnamectl set-hostname "${HOSTNAME_FQDN}"

echo "==> Writing /etc/hosts maze entries"
if ! grep -q '# maze bare-metal private' /etc/hosts; then
  {
    echo ""
    echo "# maze bare-metal private"
    printf '%s\n' "${HOSTS_BLOCK}"
  } >> /etc/hosts
fi

echo "==> apt update / upgrade"
apt-get update -y
apt-get upgrade -y

echo "==> Installing base packages"
apt-get install -y \
  emacs-nox vim curl wget jq htop iotop traceroute net-tools \
  ca-certificates gnupg lsb-release apt-transport-https \
  chrony software-properties-common unzip \
  nftables unattended-upgrades apt-listchanges

echo "==> Security unattended-upgrades (no automatic reboot)"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat >/etc/apt/apt.conf.d/51maze-unattended <<'EOF'
Unattended-Upgrade::Allowed-Origins {
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
systemctl enable --now unattended-upgrades || true

echo "==> Time sync (chrony)"
systemctl enable --now chrony
timedatectl set-ntp true || true

echo "==> Disable swap (required by kubelet)"
swapoff -a || true
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

echo "==> Kernel modules for Kubernetes / Cilium"
cat >/etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
EOF
sysctl --system >/dev/null

echo "==> UFW firewall"
apt-get install -y ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
# SSH — VPN / cluster pods (WireGuard hairpin) / jump host only. Not public internet.
# vRack full-trust rule below also covers private-IP SSH between nodes.
ufw allow from "${VPN_CIDR}" to any port 22 proto tcp comment 'ssh-vpn'
ufw allow from "${POD_CIDR}" to any port 22 proto tcp comment 'ssh-pods'
if [[ -n "${JUMP_IP:-}" ]]; then
  ufw allow from "${JUMP_IP}" to any port 22 proto tcp comment 'ssh-jump'
fi
# Kubernetes API — private network always; optional jump host via JUMP_IP env.
# Also allow pod CIDR: kube-proxy DNAT of ClusterIP kubernetes to the *local*
# node IP keeps the pod source address, so UFW INPUT sees 10.244.0.0/16 → :6443.
# Without this, ~1/N API calls from in-cluster clients (e.g. GitLab runner exec/
# cleanup) time out when LB picks the local apiserver endpoint.
ufw allow from "${VRACK_CIDR}" to any port 6443 proto tcp comment 'apiserver-vrack'
ufw allow from "${POD_CIDR}" to any port 6443 proto tcp comment 'apiserver-pods'
if [[ -n "${JUMP_IP:-}" ]]; then
  ufw allow from "${JUMP_IP}" to any port 6443 proto tcp comment 'apiserver-jump'
fi
# etcd / kubelet / control-plane ports — private only
ufw allow from "${VRACK_CIDR}" to any port 2379:2380 proto tcp
ufw allow from "${VRACK_CIDR}" to any port 10250 proto tcp
ufw allow from "${VRACK_CIDR}" to any port 10257 proto tcp
ufw allow from "${VRACK_CIDR}" to any port 10259 proto tcp
# NodePort range — TCP kept for optional diagnostics; WireGuard needs UDP.
ufw allow 30000:32767/tcp
ufw allow 31820/udp comment 'wireguard'
# HTTP/HTTPS not exposed publicly (VPN-only + DNS-01). Still allow from vRack for node health.
# Cilium / VXLAN / health (adjust if CNI changes)
ufw allow 8472/udp
ufw allow 4240/tcp
# Full trust on private network
ufw allow from "${VRACK_CIDR}"
ufw --force enable
ufw status verbose

# Ubuntu 25+/26 AppArmor ships a wg-quick profile that breaks linuxserver
# WireGuard in containers (busybox readlink → Permission denied). Disable it.
if [[ -f /etc/apparmor.d/wg-quick ]]; then
  mkdir -p /etc/apparmor.d/disable
  ln -sfn /etc/apparmor.d/wg-quick /etc/apparmor.d/disable/wg-quick
  apparmor_parser -R /etc/apparmor.d/wg-quick 2>/dev/null || true
fi
if [[ -f /etc/apparmor.d/wg ]]; then
  mkdir -p /etc/apparmor.d/disable
  ln -sfn /etc/apparmor.d/wg /etc/apparmor.d/disable/wg
  apparmor_parser -R /etc/apparmor.d/wg 2>/dev/null || true
fi

echo "==> Host basics complete on $(hostname) (${PRIVATE_IP})"
EOS
)"

if [[ "${1:-}" == "--remote" ]]; then
  require_ssh_key
  JUMP_IP="${JUMP_IP:-$(curl -4 -fsS --max-time 5 ifconfig.me 2>/dev/null || true)}"
  HOSTS_B64="$(printf '%s\n' \
    "${BM01_PRIVATE} ${BM01_NAME}" \
    "${BM02_PRIVATE} ${BM02_NAME}" \
    "${BM03_PRIVATE} ${BM03_NAME}" \
    "${VRACK_GW} maze-gw" | base64 -w0)"
  declare -a NAMES=("${BM01_NAME}" "${BM02_NAME}" "${BM03_NAME}")
  declare -a HOSTS=("${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}")
  declare -a IPS=("${BM01_PRIVATE}" "${BM02_PRIVATE}" "${BM03_PRIVATE}")
  for i in 0 1 2; do
    echo "======== ${NAMES[$i]} (${HOSTS[$i]}) ========"
    remote "${HOSTS[$i]}" \
      "sudo JUMP_IP='${JUMP_IP}' bash -s -- ${NAMES[$i]} ${IPS[$i]} ${HOSTS_B64} ${VRACK_CIDR} ${VPN_CIDR:-10.8.0.0/24} ${POD_CIDR:-10.244.0.0/16}" \
      <<<"${HOST_BASICS_BODY}"
  done
  echo "✓ Host basics applied on all nodes"
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root on the node, or use --remote from a jump host" >&2
  exit 1
fi

bash -c "${HOST_BASICS_BODY}" -- "${1:?hostname}" "${2:?private_ip}" "${3:?hosts_b64}" "${4:-${VRACK_CIDR}}" "${5:-${VPN_CIDR:-10.8.0.0/24}}" "${6:-${POD_CIDR:-10.244.0.0/16}}"
