#!/usr/bin/env bash
#
# Validació dels quatre routers MikroTik de la delegació:
#   - estat de les VM i arrencada
#   - adreçament i interfícies
#   - connectivitat entre routers (ping de cada router als altres tres)
#   - sortida a Internet (IP pública i nom de domini)
#   - accés SSH personal (sysadmin) i clau del professor (auditor)
#
# Ús: validate_routers.sh [-o fitxer_evidencies] [--reboot]
#   --reboot  reinicia els routers abans de validar (prova de persistència)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
source "${PROJECT_ROOT}/infrastructure/bash/common.sh"

NET="${NET_PREFIX:-10.${DELEGATION_ID:-2}}"
OUTPUT="${PROJECT_ROOT}/docs/evidencies/validacio.txt"
REBOOT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT="$2"; shift 2 ;;
        --reboot) REBOOT=true; shift ;;
        *) log_err "Opció desconeguda: $1"; exit 1 ;;
    esac
done

ROUTERS=(mikrotik0 mikrotik1 mikrotik2 mikrotik3)
# Adreça de trànsit de cada router (la que s'usa per a SSH i ping)
declare -A MGMT_IP=(
    [mikrotik0]="${NET}.0.225"
    [mikrotik1]="${NET}.0.226"
    [mikrotik2]="${NET}.0.230"
    [mikrotik3]="${NET}.0.234"
)
EDGE_PORT=2200

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10 -i "$SYSADMIN_PRIVATE_KEY_FILE")

# Executa una ordre RouterOS a un router; els interns via ProxyJump per mikrotik0
ros() {
    local router="$1"; shift
    if [[ "$router" == mikrotik0 ]]; then
        ssh "${SSH_OPTS[@]}" -p "$EDGE_PORT" "${SSH_USER}@127.0.0.1" "$*"
    else
        ssh "${SSH_OPTS[@]}" \
            -o "ProxyCommand=ssh ${SSH_OPTS[*]} -p ${EDGE_PORT} -W %h:%p ${SSH_USER}@127.0.0.1" \
            "${SSH_USER}@${MGMT_IP[$router]}" "$*"
    fi
}

start_routers() {
    local r
    for r in "${ROUTERS[@]}"; do
        if ! "$VBOXMANAGE_BIN" list runningvms | grep -q "\"$r\""; then
            log_info "Arrencant $r"
            "$VBOXMANAGE_BIN" startvm "$r" --type headless >/dev/null
        fi
    done
}

wait_routers() {
    local r elapsed
    for r in "${ROUTERS[@]}"; do
        elapsed=0
        until ros "$r" ":put ok" >/dev/null 2>&1; do
            sleep 5
            elapsed=$((elapsed + 5))
            if (( elapsed >= 180 )); then
                log_err "$r no respon per SSH"
                return 1
            fi
        done
        log_ok "$r accessible per SSH"
    done
}

ping_summary() {
    # Retorna la línia de resum (sent/received/packet-loss) d'un ping RouterOS
    ros "$1" "/ping $2 count=3" 2>&1 | tr -d '\r' | grep -E 'sent=|failure|invalid' | tail -1
}

mkdir -p "$(dirname "$OUTPUT")"
: > "$OUTPUT"
out() { echo -e "$*" | tee -a "$OUTPUT"; }

start_routers
wait_routers || exit 1

if [[ "$REBOOT" == true ]]; then
    log_info "Reiniciant els routers (prova de persistència)"
    # Ordre invers: els routers interns s'abasten a través de mikrotik0,
    # que per tant ha de ser l'últim a reiniciar-se.
    for ((i=${#ROUTERS[@]}-1; i>=0; i--)); do
        ros "${ROUTERS[$i]}" "/system reboot" </dev/null >/dev/null 2>&1 || true
        sleep 2
    done
    sleep 20
    wait_routers || exit 1
fi

FAILS=0
check() {
    # check <descripció> <resultat>
    if [[ "$2" == *"packet-loss=0%"* || "$2" == OK* ]]; then
        out "  [OK]   $1  ${2#OK}"
    else
        out "  [FAIL] $1  $2"
        FAILS=$((FAILS + 1))
    fi
}

out "VirtualCorp - Delegació ${DELEGATION_ID:-2} (${NET}.0.0/16) - Validació de routers"
out "Data: $(date '+%Y-%m-%d %H:%M:%S')  Reinici previ: $REBOOT"
out "=============================================================="

for r in "${ROUTERS[@]}"; do
    out "\n### $r (${MGMT_IP[$r]})"
    out "$(ros "$r" ':put ("identity=" . [/system identity get name] . "  uptime=" . [/system resource get uptime] . "  version=" . [/system resource get version])' | tr -d '\r')"
    out "$(ros "$r" '/ip address print without-paging' | tr -d '\r')"

    out "-- Connectivitat entre routers"
    for other in "${ROUTERS[@]}"; do
        [[ "$other" == "$r" ]] && continue
        check "ping $other ${MGMT_IP[$other]}" "$(ping_summary "$r" "${MGMT_IP[$other]}")"
    done

    out "-- Sortida a Internet"
    check "ping 1.1.1.1" "$(ping_summary "$r" 1.1.1.1)"
    resolved="$(ros "$r" ':put [:resolve www.google.com]' 2>&1 | tr -d '\r')"
    if [[ "$resolved" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        check "DNS www.google.com -> $resolved" "OK"
        check "ping www.google.com" "$(ping_summary "$r" "$resolved")"
    else
        check "DNS www.google.com" "$resolved"
    fi

    out "-- Accés SSH"
    check "sysadmin amb clau personal (vcorp_sysadmin)" "OK"
    keys="$(ros "$r" '/user ssh-keys print terse without-paging' | tr -d '\r')"
    if grep -q 'user=auditor.*vcorp_auditor@virtualcorp' <<<"$keys"; then
        check "clau del professor instal·lada a l'usuari auditor" "OK"
    else
        check "clau del professor instal·lada a l'usuari auditor" "no trobada"
    fi
    if grep -q 'user=sysadmin' <<<"$keys"; then
        check "clau personal instal·lada a l'usuari sysadmin" "OK"
    else
        check "clau personal instal·lada a l'usuari sysadmin" "no trobada"
    fi
    out "$(ros "$r" '/user print terse without-paging where name~"admin|auditor|sysadmin"' | tr -d '\r')"
done

out "\n=============================================================="
if (( FAILS == 0 )); then
    out "RESULTAT: totes les comprovacions correctes"
else
    out "RESULTAT: $FAILS comprovacions fallides"
fi

exit $(( FAILS > 0 ))
