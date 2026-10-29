#!/bin/bash
# Proves dels 4 routers de la delegació 02:
#   adreces IP, ping entre routers, sortida a Internet i usuaris/claus SSH.
#
# Ús (des de l'arrel del projecte):
#   ./automation/scripts/validate_routers.sh [fitxer_de_sortida]

SSH="ssh -F configs/ssh/ssh_config"
ROUTERS="mikrotik0 mikrotik1 mikrotik2 mikrotik3"
IPS="10.2.0.225 10.2.0.226 10.2.0.230 10.2.0.234"
SORTIDA="${1:-docs/evidencies/validacio.txt}"

# 1. Engegar els routers (si ja estan engegats, no passa res).
#    S'espera perquè arrenquin i RIP tingui temps d'aprendre les rutes.
for r in $ROUTERS; do
    VBoxManage startvm "$r" --type headless 2>/dev/null && sleep 25
done

mkdir -p "$(dirname "$SORTIDA")"
echo "Validació delegació 02 - $(date '+%Y-%m-%d %H:%M')" | tee "$SORTIDA"

# 2. Proves de cada router
for r in $ROUTERS; do
    echo "" | tee -a "$SORTIDA"
    echo "===== $r =====" | tee -a "$SORTIDA"

    # Temps engegat (per comprovar els reinicis) i adreces IP
    $SSH "$r" "/system resource print" | grep uptime | tee -a "$SORTIDA"
    $SSH "$r" "/ip address print" | tee -a "$SORTIDA"

    # Ping als routers i a Internet (per IP i per nom)
    for desti in $IPS 1.1.1.1 www.google.com; do
        resultat=$($SSH "$r" "/ping $desti count=3" | grep "sent=")
        echo "ping $desti: $resultat" | tee -a "$SORTIDA"
    done

    # Usuaris i claus SSH (sysadmin = jo, auditor = professor)
    $SSH "$r" "/user print" | tee -a "$SORTIDA"
    $SSH "$r" "/user ssh-keys print" | tee -a "$SORTIDA"
done
