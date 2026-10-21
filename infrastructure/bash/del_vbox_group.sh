#!/bin/bash
set -euo pipefail

# Carregar les funcions d'ajuda i variables de configuració
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Comprovar la disponibilitat de VBoxManage
if [ -z "$VBOXMANAGE_BIN" ]; then
    log_err "VBoxManage no està instal·lat o no es troba al PATH."
    exit 1
fi

# Funció per mostrar l'ajuda
show_help() {
    cat << EOF
Ús: $0 [OPCIONS] [NOM_DEL_GRUP]

Esborra les màquines virtuals d'un grup de VirtualBox i tots els seus subgrups.

Opcions:
  -r, --routers    Esborra el grup de routers (${VM_ROUTERS_GROUP:-no definit})
  -a, --all        Esborra el grup arrel (${VBOX_ROOT_GROUP:-no definit})
  -h, --help       Mostra aquest missatge d'ajuda

Exemples:
  $0 /VCorp
  $0 -r
  $0 --all
EOF
}

TARGET_GROUP=""

# Processament d'arguments/flags (facilita afegir noves opcions en el futur)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--routers)
            TARGET_GROUP="${VM_ROUTERS_GROUP:-}"
            shift
            ;;
        -a|--all)
            TARGET_GROUP="${VBOX_ROOT_GROUP:-}"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            log_err "Opció desconeguda: $1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$TARGET_GROUP" ]; then
                TARGET_GROUP="$1"
            else
                log_err "Error: S'han especificat múltiples grups o paràmetres no vàlids ('$1')."
                exit 1
            fi
            shift
            ;;
    esac
done

# Validar que s'hagi definit un grup
if [ -z "$TARGET_GROUP" ]; then
    log_err "Error: Cal especificar un grup o utilitzar un flag de selecció (-r, -a)."
    show_help
    exit 1
fi

# Normalitzar el grup d'entrada (comença per '/' i sense '/' al final)
TARGET_GROUP="/${TARGET_GROUP#/}"
TARGET_GROUP="${TARGET_GROUP%/}"

log_info "Cercant màquines virtuals al grup '$TARGET_GROUP' i subgrups..."

# Recórrer totes les MVs pel seu UUID
VMS=$("$VBOXMANAGE_BIN" list vms | sed -E 's/.*\{([^}]+)\}/\1/')

if [ -z "$VMS" ]; then
    log_warn "No s'ha trobat cap màquina virtual."
    exit 0
fi

DELETED_COUNT=0

for UUID in $VMS; do
    # Extraure informació de la MV
    INFO=$("$VBOXMANAGE_BIN" showvminfo "$UUID" --machinereadable)
    VM_NAME=$(echo "$INFO" | grep '^name=' | cut -d'=' -f2 | tr -d '"')
    GROUPS_LINE=$(echo "$INFO" | grep '^groups=' | cut -d'=' -f2 | tr -d '"')
    VM_STATE=$(echo "$INFO" | grep '^VMState=' | cut -d'=' -f2 | tr -d '"')

    # Una MV pot pertànyer a diversos grups separats per comes
    IFS=',' read -ra VM_GROUPS <<< "$GROUPS_LINE"
    
    MATCH=false
    for g in "${VM_GROUPS[@]}"; do
        # Normalitzar el path del grup de la MV
        g="/${g#/}"
        g="${g%/}"

        # Coincidència exacta ($g == /VCorp) O subgrup ($g comença per /VCorp/)
        if [ "$g" = "$TARGET_GROUP" ] || [[ "$g" == "$TARGET_GROUP/"* ]]; then
            MATCH=true
            break
        fi
    done

    if [ "$MATCH" = true ]; then
        log_info "-> Trobada: '$VM_NAME' ($UUID) a '$GROUPS_LINE'"

        # Aturar la MV si està en execució abans d'esborrar
        if [ "$VM_STATE" = "running" ] || [ "$VM_STATE" = "paused" ]; then
            log_info "   Apagant la màquina virtual..."
            "$VBOXMANAGE_BIN" controlvm "$UUID" poweroff 2>/dev/null || true
            sleep 2
        fi

        # Desregistrar i eliminar tots els fitxers del disc
        log_info "   Eliminant fitxers i unregistering..."
        "$VBOXMANAGE_BIN" unregistervm "$UUID" --delete
        DELETED_COUNT=$((DELETED_COUNT + 1))
    fi
done

log_info "Completat. S'han eliminat $DELETED_COUNT màquines virtuals."
