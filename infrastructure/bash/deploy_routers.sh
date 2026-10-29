#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"


check_prerequisites

# Crea el template pel router
# create_router_template

# Delegacio 02 -> 10.2.0.0/16

# Desplegament de mikrotik0 (surt a internet, DMZ i zona privada del CPD)
create_router "mikrotik0" 2200 \
  --intnets "r0-r1" "dmz" "privada" \
  --ips "10.2.0.225/30" "10.2.0.193/27" "10.2.0.129/26" \
  --nat

# Desplegament de mikrotik1 (planta baixa)
create_router "mikrotik1" 2201 \
  --intnets "r0-r1" "r1-r2" "pl0" \
  --ips "10.2.0.226/30" "10.2.0.229/30" "10.2.0.1/25" \
  --gateway "10.2.0.225"

# Desplegament de mikrotik2 (planta 1 i 2)
create_router "mikrotik2" 2202 \
  --intnets "r1-r2" "r2-r3" "pl1" "pl2" \
  --ips "10.2.0.230/30" "10.2.0.233/30" "10.2.1.1/24" "10.2.2.1/24" \
  --gateway "10.2.0.229"

# Desplegament de mikrotik3 (planta 3 i direccio)
create_router "mikrotik3" 2203 \
  --intnets "r2-r3" "pl3" "pl3-direccio" \
  --ips "10.2.0.234/30" "10.2.3.1/25" "10.2.3.129/25" \
  --gateway "10.2.0.233"

log_info "=========================================="
log_info "[+] Routers desplegats correctament."
log_info "=========================================="
