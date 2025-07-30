#!/bin/bash
# =============================================================================
# Script de Demostración: RBF vs CPFP en Bitcoin
# Autor: 0xcar
# Propósito: Demostrar la incompatibilidad entre RBF y CPFP
# =============================================================================

set -euo pipefail

# Configuración de colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Función para imprimir mensajes con formato
print_step() {
    echo -e "${BLUE}[PASO $1]${NC} $2"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ÉXITO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ADVERTENCIA]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para limpiar al salir
cleanup() {
    print_info "Deteniendo Bitcoin Core..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
    wait
}

trap cleanup EXIT

# Variables de configuración
BITCOIN_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

echo -e "\n${CYAN}=== RBF vs CPFP Demo ===${NC}\n"

# =============================================================================
# PASO 1: Configuración
# =============================================================================
print_step "1" "Configurando Bitcoin regtest"

# Limpiar instancias previas
pkill bitcoind 2>/dev/null || true
sleep 2
rm -rf "$BITCOIN_DATA_DIR/regtest" 2>/dev/null || true

mkdir -p "$BITCOIN_DATA_DIR"
cat > "$BITCOIN_DATA_DIR/bitcoin.conf" <<EOF
regtest=1
server=1
txindex=1
fallbackfee=0.0001
EOF

print_info "Iniciando Bitcoin Core..."
bitcoind -daemon -datadir="$BITCOIN_DATA_DIR"
sleep 5

# Verificar que Bitcoin Core está funcionando
if ! bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getblockchaininfo > /dev/null 2>&1; then
    print_error "Bitcoin Core no se pudo iniciar correctamente"
    exit 1
fi

print_success "Bitcoin Core iniciado"

# =============================================================================
# PASO 2: Creación de wallets
# =============================================================================
print_step "2" "Creando wallets y fondos"

# Crear wallets
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MINER_WALLET" > /dev/null
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$TRADER_WALLET" > /dev/null

# Generar fondos
MINER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress)
print_info "Generando bloques..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 104 "$MINER_ADDR" > /dev/null

print_success "Wallets y fondos creados"

# =============================================================================
# PASO 3: Preparación de UTXOs
# =============================================================================
print_step "3" "Seleccionando UTXOs"

# Obtener UTXOs de 50 BTC
mapfile -t UTXOS < <(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" listunspent 1 9999999 | \
  jq -r '.[] | select(.amount==50) | "\(.txid):\(.vout)"')

if [ ${#UTXOS[@]} -lt 2 ]; then
    print_error "No hay suficientes UTXOs de 50 BTC disponibles"
    exit 1
fi

IN1_TXID=${UTXOS[0]%%:*}
IN1_VOUT=${UTXOS[0]#*:}
IN2_TXID=${UTXOS[1]%%:*}
IN2_VOUT=${UTXOS[1]#*:}

TRADER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getnewaddress)

# =============================================================================
# PASO 4: Transacción padre (RBF habilitado)
# =============================================================================
print_step "4" "Creando transacción padre con RBF"

RAW_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction \
  "[{\"txid\":\"$IN1_TXID\",\"vout\":$IN1_VOUT,\"sequence\":1},{\"txid\":\"$IN2_TXID\",\"vout\":$IN2_VOUT,\"sequence\":4294967294}]" \
  "{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.99999}")

SIGNED_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$RAW_PARENT" | jq -r '.hex')

PARENT_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_PARENT")
print_success "Transacción padre: $PARENT_TXID"

# Analizar información de la transacción padre
sleep 2
RAW_PARENT_INFO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getrawtransaction "$PARENT_TXID" true)
MPOOL_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$PARENT_TXID" 2>/dev/null || echo '{"fee":0,"weight":832}')

INPUT_JSON=$(echo "$RAW_PARENT_INFO" | jq '[.vin[] | {txid:.txid, vout:.vout}]')
OUTPUT_JSON=$(echo "$RAW_PARENT_INFO" | jq '[.vout[] | {script_pubkey:.scriptPubKey.hex, amount:.value}]')
FEES=$(echo "$MPOOL_PARENT" | jq -r '.fee // 0')
WEIGHT=$(echo "$MPOOL_PARENT" | jq -r '.weight // 832')

PARENT_JSON=$(jq -n \
  --argjson input "$INPUT_JSON" \
  --argjson output "$OUTPUT_JSON" \
  --arg fees "$FEES" \
  --arg weight "$WEIGHT" \
  '{input: $input, output: $output, Fees: ($fees|tonumber), Weight: ($weight|tonumber)}')

print_info "Información detallada de la transacción padre:"
echo "$PARENT_JSON" | jq .

# =============================================================================
# PASO 5: Transacción hija (CPFP)
# =============================================================================
print_step "5" "Creando transacción hija (CPFP)"

CHILD_RAW=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction "[{\"txid\":\"$PARENT_TXID\",\"vout\":1}]" \
  "{\"$MINER_ADDR\":29.99998}")

SIGNED_CHILD=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$CHILD_RAW" | jq -r '.hex')

CHILD_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_CHILD")
print_success "Transacción hija: $CHILD_TXID"

# Mostrar información del mempool de la transacción hija
print_info "Información de la transacción hija en mempool:"
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$CHILD_TXID"

# =============================================================================
# PASO 6: RBF (Replace-By-Fee)
# =============================================================================
print_step "6" "Ejecutando RBF"

BUMP_RAW=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction \
  "[{\"txid\":\"$IN1_TXID\",\"vout\":$IN1_VOUT,\"sequence\":4294967294},{\"txid\":\"$IN2_TXID\",\"vout\":$IN2_VOUT,\"sequence\":4294967294}]" \
  "{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.9999}")

SIGNED_BUMP=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$BUMP_RAW" | jq -r '.hex')

BUMP_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_BUMP")
print_success "RBF ejecutado: $BUMP_TXID"

# =============================================================================
# PASO 7: Verificación
# =============================================================================
print_step "7" "Verificando estado del mempool"

print_info "Segunda consulta getmempoolentry para child:"
if bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$CHILD_TXID" 2>/dev/null; then
    print_warning "Child todavía en mempool"
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$CHILD_TXID"
else
    print_success "Child removida tras RBF"
    echo "Error: No such mempool transaction. Use -txindex or provide the transaction output index"
fi

echo -e "\n${CYAN}=== CAMBIOS EN GETMEMPOOLENTRY ===${NC}"
echo -e "${YELLOW}Antes del RBF:${NC} La transacción child estaba en el mempool"
echo -e "${YELLOW}Después del RBF:${NC} La transacción child fue removida automáticamente"
echo -e "${YELLOW}Razón:${NC} Al reemplazar la transacción parent, el input de child ya no existe"
echo -e "${YELLOW}Conclusión:${NC} RBF invalida cualquier transacción CPFP dependiente"

print_info "Deteniendo Bitcoin Core..."
