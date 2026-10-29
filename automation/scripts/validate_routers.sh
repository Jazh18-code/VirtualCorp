#!/bin/bash
# Script per provar els 4 routers (delegacio 02)
# Mira les IPs, fa ping entre routers i a internet, i mostra els usuaris i claus ssh
# S'executa des de la carpeta del projecte: make validate

SSH="ssh -F configs/ssh/ssh_config"
ROUTERS="mikrotik0 mikrotik1 mikrotik2 mikrotik3"
IPS="10.2.0.225 10.2.0.226 10.2.0.230 10.2.0.234"
SORTIDA="${1:-docs/evidencies/validacio.txt}"

# engego els routers (si ja estan engegats dona error pero no passa res)
# espero 25 segons perque arrenquin i el RIP aprengui les rutes
for r in $ROUTERS; do
    VBoxManage startvm "$r" --type headless 2>/dev/null && sleep 25
done

mkdir -p docs/evidencies
echo "Proves delegacio 02 - $(date '+%Y-%m-%d %H:%M')" | tee "$SORTIDA"

for r in $ROUTERS; do
    echo "" | tee -a "$SORTIDA"
    echo "===== $r =====" | tee -a "$SORTIDA"

    # uptime (per veure si s'ha reiniciat) i les IPs
    $SSH "$r" "/system resource print" | grep uptime | tee -a "$SORTIDA"
    $SSH "$r" "/ip address print" | tee -a "$SORTIDA"

    # ping als routers, a una ip d'internet i a un nom (per provar el dns)
    for desti in $IPS 1.1.1.1 www.google.com; do
        resultat=$($SSH "$r" "/ping $desti count=3" | grep "sent=")
        echo "ping $desti: $resultat" | tee -a "$SORTIDA"
    done

    # usuaris i claus (sysadmin soc jo, auditor es el profe)
    $SSH "$r" "/user print" | tee -a "$SORTIDA"
    $SSH "$r" "/user ssh-keys print" | tee -a "$SORTIDA"
done
