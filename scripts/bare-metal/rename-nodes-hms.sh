#!/usr/bin/env bash
# rename-nodes-hms.sh — OS hostname + /etc/hosts for HMS names.
# Kubernetes node object rename still requires drain/reset/rejoin per CP
# (see docs/host-naming.md). This script updates host identity used by SSH.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

# slot -> new name
declare -A NEW_NAMES=(
  ["${BM01_NAME:-bm-01}"]="hms-conqueror-30bd"
  ["${BM02_NAME:-bm-02}"]="hms-vengeful-4d19"
  ["${BM03_NAME:-bm-03}"]="hms-dreadnought-3623"
)

# Prefer renaming from current inventory SSH targets
declare -a HOSTS=("${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}")
declare -a OLD_NAMES=("${BM01_NAME}" "${BM02_NAME}" "${BM03_NAME}")
declare -a NEW_LIST=("hms-conqueror-30bd" "hms-vengeful-4d19" "hms-dreadnought-3623")
declare -a IPS=("${BM01_PRIVATE}" "${BM02_PRIVATE}" "${BM03_PRIVATE}")

HOSTS_BLOCK=$(printf '%s\n' \
  "${IPS[0]} ${NEW_LIST[0]}" \
  "${IPS[1]} ${NEW_LIST[1]}" \
  "${IPS[2]} ${NEW_LIST[2]}" \
  "${VRACK_GW:-192.168.0.1} maze-gw")

for i in 0 1 2; do
  echo "======== ${OLD_NAMES[$i]} → ${NEW_LIST[$i]} (${HOSTS[$i]}) ========"
  remote "${HOSTS[$i]}" "sudo bash -s" <<EOS
set -euo pipefail
NEW='${NEW_LIST[$i]}'
hostnamectl set-hostname "\$NEW"
# Replace maze bare-metal private block
if grep -q '# maze bare-metal private' /etc/hosts; then
  sed -i '/# maze bare-metal private/,+4d' /etc/hosts
fi
{
  echo ''
  echo '# maze bare-metal private'
  printf '%s\n' '${HOSTS_BLOCK}'
} >> /etc/hosts
echo "hostname=\$(hostname) hosts:"
grep -A5 '# maze bare-metal private' /etc/hosts || true
EOS
done

echo "OS hostnames updated. Next: drain/reset/rejoin each kubeadm node so Kubernetes Node names match,"
echo "then set storage_nodes in terraform.tfvars to the HMS names and tofu apply."
