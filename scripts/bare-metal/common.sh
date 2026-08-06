#!/usr/bin/env bash
# Shared helpers for bare-metal bootstrap scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INVENTORY_FILE="${BARE_METAL_INVENTORY:-${SCRIPT_DIR}/inventory.env}"
if [[ ! -f "${INVENTORY_FILE}" ]]; then
  cat >&2 <<EOF
ERROR: bare-metal inventory not found: ${INVENTORY_FILE}

  cp ${SCRIPT_DIR}/inventory.env.example ${SCRIPT_DIR}/inventory.env
  # edit SSH hosts, public/private IPs, LB VIP
  # or: export BARE_METAL_INVENTORY=/path/to/your/inventory.env
EOF
  exit 1
fi
# shellcheck disable=SC1090
source "${INVENTORY_FILE}"

require_inventory() {
  local missing=()
  local v
  for v in \
    BM01_NAME BM02_NAME BM03_NAME \
    BM01_SSH BM02_SSH BM03_SSH \
    BM01_PUBLIC BM02_PUBLIC BM03_PUBLIC \
    BM01_PRIVATE BM02_PRIVATE BM03_PRIVATE \
    SSH_USER SSH_KEY \
    CONTROL_PLANE_ENDPOINT POD_CIDR SERVICE_CIDR K8S_VERSION
  do
    if [[ -z "${!v:-}" ]]; then
      missing+=("${v}")
    fi
  done
  if ((${#missing[@]})); then
    echo "ERROR: inventory missing values: ${missing[*]}" >&2
    echo "  file: ${INVENTORY_FILE}" >&2
    exit 1
  fi
  # Refuse example placeholders so we never bootstrap against docs defaults
  if [[ "${BM01_SSH}" == *example.invalid ]] || [[ "${BM01_PUBLIC}" == 203.0.113.* ]]; then
    echo "ERROR: ${INVENTORY_FILE} still has example placeholders — fill in real hosts/IPs" >&2
    exit 1
  fi
}

require_inventory

ssh_opts=(-i "${SSH_KEY}" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20)

remote() {
  local host="$1"
  shift
  ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "$@"
}

remote_sudo_bash() {
  local host="$1"
  local script="$2"
  ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "sudo bash -s" <<<"${script}"
}

all_ssh_hosts() {
  printf '%s\n' "${BM01_SSH}" "${BM02_SSH}" "${BM03_SSH}"
}

require_ssh_key() {
  if [[ ! -f "${SSH_KEY}" ]]; then
    echo "ERROR: SSH key not found: ${SSH_KEY}" >&2
    exit 1
  fi
  chmod 600 "${SSH_KEY}" || true
}
