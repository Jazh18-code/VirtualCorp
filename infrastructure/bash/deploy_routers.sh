#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"

# Prefix de la delegació (10.xx), definit a .env amb DELEGATION_ID
NET="${NET_PREFIX:-10.${DELEGATION_ID:-2}}"

check_prerequisites

# Crea el template pel router
# create_router_template

# Desplegament de mikrotik0 (router0): ISP (ether1 NAT), CPD privat i DMZ
create_router "mikrotik0" 2200 \
  --intnets "r0-r1" "dmz" "privada" \
  --ips "${NET}.0.225/30" "${NET}.0.193/27" "${NET}.0.129/26" \
  --nat

# Desplegament de mikrotik1 (router1): planta baixa
create_router "mikrotik1" 2201 \
  --intnets "r0-r1" "r1-r2" "pl0" \
  --ips "${NET}.0.226/30" "${NET}.0.229/30" "${NET}.0.1/25" \
  --gateway "${NET}.0.225" \
  --dns "${NET}.0.225"

# Desplegament de mikrotik2 (router2): plantes 1 i 2
create_router "mikrotik2" 2202 \
  --intnets "r1-r2" "r2-r3" "pl1" "pl2" \
  --ips "${NET}.0.230/30" "${NET}.0.233/30" "${NET}.1.1/24" "${NET}.2.1/24" \
  --gateway "${NET}.0.229" \
  --dns "${NET}.0.225"

# Desplegament de mikrotik3 (router3): planta 3 i xarxa aïllada de direcció
create_router "mikrotik3" 2203 \
  --intnets "r2-r3" "pl3" "pl3-direccio" \
  --ips "${NET}.0.234/30" "${NET}.3.1/25" "${NET}.3.129/25" \
  --gateway "${NET}.0.233" \
  --dns "${NET}.0.225"

log_info "=========================================="
log_info "[+] Routers desplegats correctament."
log_info "=========================================="
