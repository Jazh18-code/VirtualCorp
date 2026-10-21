#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================

ROUTEROS_VERSION="${ROUTEROS_VERSION:-7.21.4}"
ROUTEROS_VDI_FILENAME="${ROUTEROS_VDI_FILENAME:-chr-${ROUTEROS_VERSION}.vdi}"
URL="${ROUTEROS_URL:-https://download.mikrotik.com/routeros/${ROUTEROS_VERSION}/${ROUTEROS_VDI_FILENAME}.zip}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts/images/chr}"
CONFIGS_DIR="${CONFIGS_DIR:-${PROJECT_ROOT}/configs}"
SSH_PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR}/ssh}"
ROUTEROS_VDI_PATH="${ROUTEROS_VDI_PATH:-${ARTIFACTS_DIR}/${ROUTEROS_VDI_FILENAME}}"

VM_NAME="${ROUTEROS_VM_NAME:-routeros_template}"
BOX_NAME="${ROUTEROS_BOX_NAME:-routeros-base}"
BOX_FILE="${ROUTEROS_BOX_FILE:-${ARTIFACTS_DIR}/${BOX_NAME}.box}"

SSH_PORT=2222

AUDIT_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"
SYSADMIN_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"
VBOXMANAGE_BIN="${VBOXMANAGE_BIN:-$(command -v VBoxManage 2>/dev/null || command -v vboxmanage 2>/dev/null || true)}"

# Colors ANSI
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# =========================
# DEPENDENCIES
# =========================

command -v vagrant >/dev/null 2>&1 || { log_err "Vagrant missing"; exit 1; }
[[ -n "$VBOXMANAGE_BIN" ]] || { log_err "VirtualBox missing"; exit 1; }

# =========================
# HELP
# =========================

usage() {
cat <<EOF
Usage: $0 [-f]

-f Force rebuild
EOF
}

FORCE=false
while getopts "fh" opt; do
  case $opt in
    f) FORCE=true ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# =========================
# CLEANUP
# =========================

if [[ "$FORCE" == true ]]; then
  log_info "Force cleanup"

  # 1. Apagar VM si està running
  if VBoxManage list runningvms | grep -q "$VM_NAME"; then
    log_info "VM is running -> powering off"
    VBoxManage controlvm "$VM_NAME" poweroff || true
    sleep 3
  fi

  # 2. Intent normal shutdown (si existeix però no està running)
  VBoxManage controlvm "$VM_NAME" acpipowerbutton 2>/dev/null || true
  sleep 5

  # 3. Forçar estat inconsistent
  VBoxManage unregistervm "$VM_NAME" --delete 2>/dev/null || true

  # 4. Si queda carpeta residual (IMPORTANT)
  rm -rf "$HOME/VirtualBox VMs/$VM_NAME" || true

  # 5. Box cleanup
  vagrant box remove "$BOX_NAME" --force 2>/dev/null || true

  # 6. Fitxer box local
  rm -f "$BOX_FILE" || true

  log_ok "Cleanup completed"
fi

# =========================
# CHECK BOX EXISTS
# =========================

if vagrant box list | grep -q "$BOX_NAME" && [[ "$FORCE" == false ]]; then
  log_ok "Box already exists"
  exit 0
fi

mkdir -p "$ARTIFACTS_DIR"

# =========================
# DOWNLOAD CHR
# =========================

if [[ ! -f "$ROUTEROS_VDI_PATH" ]]; then
  log_info "Downloading CHR..."
  ZIP_FILE="${ARTIFACTS_DIR}/chr.zip"

  curl -L "$URL" -o "$ZIP_FILE"
  unzip -o "$ZIP_FILE" -d "$ARTIFACTS_DIR"
  rm -f "$ZIP_FILE"
fi

# =========================
# CREATE VM
# =========================

log_info "Creating VM"

"$VBOXMANAGE_BIN" createvm --name "$VM_NAME" --register

"$VBOXMANAGE_BIN" modifyvm "$VM_NAME" \
  --memory 256 \
  --cpus 1 \
  --nic1 nat

"$VBOXMANAGE_BIN" modifyvm "$VM_NAME" --natpf1 "ssh,tcp,127.0.0.1,${SSH_PORT},,22"


"$VBOXMANAGE_BIN" storagectl "$VM_NAME" \
  --name "SATA" \
  --add sata \
  --controller IntelAhci

"$VBOXMANAGE_BIN" storageattach "$VM_NAME" \
  --storagectl "SATA" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "$ROUTEROS_VDI_PATH"

# =========================
# START VM
# =========================

log_info "Starting VM"
"$VBOXMANAGE_BIN" startvm "$VM_NAME" --type headless

# =========================
# WAIT SSH
# =========================

log_info "Cleaning SSH known_hosts entry"

ssh-keygen -R "[127.0.0.1]:$SSH_PORT" 2>/dev/null || true

log_info "Waiting SSH..."

until ssh -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -p "$SSH_PORT" \
  admin@127.0.0.1 " /system identity print " \
  >/dev/null 2>&1
do
  log_info "Waiting SSH..."
  sleep 5
done

# =========================
# PROVISION ROUTEROS
# =========================

log_info "Configuring RouterOS users + SSH"

ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
     -p "$SSH_PORT" admin@127.0.0.1 <<EOF

# enable SSH service
/ip service enable ssh

# ensure vagrant user exists (critical for Vagrant lifecycle)
/user add name=vagrant group=full password="vagrant" comment="Vagrant user" disabled=no

EOF


# =========================
# INSTALL VAGRANT KEY
# =========================

log_info "Injecting Vagrant insecure key"

scp -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -P "$SSH_PORT" \
    "$SYSADMIN_PUB_KEY_FILE" \
    admin@127.0.0.1:vagrant.pub

ssh -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p "$SSH_PORT" \
    admin@127.0.0.1 <<EOF

/user ssh-keys import user=vagrant public-key-file=vagrant.pub

EOF

# =========================
# SHUTDOWN
# =========================

log_info "Shutting down VM"

"$VBOXMANAGE_BIN" controlvm "$VM_NAME" acpipowerbutton || true
sleep 20

# =========================
# PACKAGE BOX
# =========================

log_info "Packaging box"

vagrant package \
  --base "$VM_NAME" \
  --output "$BOX_FILE"

vagrant box add "$BOX_NAME" "$BOX_FILE" --force

# =========================
# CLEANUP
# =========================

"$VBOXMANAGE_BIN" unregistervm "$VM_NAME" --delete || true

log_ok "Box ready: $BOX_NAME"
