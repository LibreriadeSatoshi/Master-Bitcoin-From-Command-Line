#!/bin/bash

# ============================================================================
# Script de Multisig Bitcoin - Ejercicio Semana 3
# Autor: 0xcar
# Descripción: Implementa un sistema multisig 2-de-2 entre Alice y Bob
# ============================================================================

set -euo pipefail

# =========================== CONFIGURACIÓN ===========================
readonly BITCOIN_DATA_DIR="$HOME/.bitcoin"
readonly MINER_WALLET="Miner"
readonly ALICE_WALLET="Alice"
readonly BOB_WALLET="Bob"
readonly MULTISIG_WALLET="Multisig"

# Colores para output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# =========================== FUNCIONES AUXILIARES ===========================

# Función para imprimir mensajes con color
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

print_section() {
    echo -e "\n${YELLOW}============ $1 ============${NC}"
}

# Limpieza total de regtest y wallets (opcional)
full_cleanup() {
    print_warning "Eliminando data previa de regtest y wallets..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
    sleep 2
    rm -rf "$BITCOIN_DATA_DIR/regtest" 2>/dev/null || true
    print_success "Data de regtest eliminada."
}

# Limpieza normal al finalizar
cleanup() {
    print_info "Deteniendo Bitcoin Core..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
    sleep 2
    print_success "Limpieza completada"
}

# Función para validar que Bitcoin Core esté funcionando
validate_bitcoin_core() {
    local retries=30
    local count=0
    while [ $count -lt $retries ]; do
        if bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getblockchaininfo > /dev/null 2>&1; then
            print_success "Bitcoin Core está funcionando correctamente"
            return 0
        fi
        ((count++))
        print_info "Esperando Bitcoin Core... intento $count/$retries"
        sleep 2
    done
    print_error "No se pudo conectar con Bitcoin Core después de $retries intentos. Revisa el log en $BITCOIN_DATA_DIR/regtest/debug.log"
    print_warning "Si tienes problemas, ejecuta: bash $0 limpiar para reiniciar desde cero."
    exit 1
}

# Función para crear y configurar Bitcoin Core
setup_bitcoin_core() {
    print_section "CONFIGURANDO BITCOIN CORE"
    mkdir -p "$BITCOIN_DATA_DIR"
    # Crear archivo de configuración optimizado
    cat > "$BITCOIN_DATA_DIR/bitcoin.conf" <<EOF
# Configuración para red de pruebas
regtest=1
server=1
txindex=1
fallbackfee=0.0001
# Optimizaciones
dbcache=300
maxmempool=50
mempoolexpiry=24
EOF
    # Si bitcoind ya está corriendo, no lo inicies de nuevo
    if pgrep -f "bitcoind.*$BITCOIN_DATA_DIR" > /dev/null; then
        print_warning "bitcoind ya está corriendo. Usando instancia existente."
    else
        print_info "Iniciando Bitcoin Core en modo regtest..."
        bitcoind -daemon -datadir="$BITCOIN_DATA_DIR"
    fi
    validate_bitcoin_core
}

# Función para crear o cargar wallets
create_wallets() {
    print_section "CREANDO O CARGANDO WALLETS"
    local wallets=("$MINER_WALLET" "$ALICE_WALLET" "$BOB_WALLET")
    for wallet in "${wallets[@]}"; do
        if bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$wallet" getwalletinfo > /dev/null 2>&1; then
            print_warning "Wallet $wallet ya existe. Cargando..."
            bitcoin-cli -datadir="$BITCOIN_DATA_DIR" loadwallet "$wallet" > /dev/null 2>&1 || true
        else
            print_info "Creando wallet: $wallet"
            bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$wallet" false false "" false true > /dev/null
            print_success "Wallet $wallet creado exitosamente"
        fi
    done
}

# Función para generar direcciones iniciales
generate_initial_addresses() {
    print_section "GENERANDO DIRECCIONES INICIALES"
    MINER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress || echo "")
    ALICE_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getnewaddress || echo "")
    BOB_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" getnewaddress || echo "")
    if [ -z "$MINER_ADDR" ] || [ -z "$ALICE_ADDR" ] || [ -z "$BOB_ADDR" ]; then
        print_error "No se pudieron generar las direcciones iniciales. Verifica que los wallets estén cargados."
        exit 1
    fi
    print_success "Dirección del Minero: $MINER_ADDR"
    print_success "Dirección de Alice: $ALICE_ADDR"
    print_success "Dirección de Bob: $BOB_ADDR"
}

# Función para financiar wallets iniciales
fund_initial_wallets() {
    print_section "FINANCIANDO WALLETS INICIALES"
    if [ -z "$MINER_ADDR" ] || [ -z "$ALICE_ADDR" ] || [ -z "$BOB_ADDR" ]; then
        print_error "Direcciones no válidas. Abortando."
        exit 1
    fi
    print_info "Generando 101 bloques para madurar las coinbase..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 101 "$MINER_ADDR" > /dev/null
    print_info "Enviando 15 BTC a Alice..."
    ALICE_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$ALICE_ADDR" 15 || echo "")
    if [ -z "$ALICE_TXID" ]; then print_error "No se pudo enviar a Alice"; exit 1; fi
    print_success "TXID Alice: $ALICE_TXID"
    print_info "Enviando 15 BTC a Bob..."
    BOB_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$BOB_ADDR" 15 || echo "")
    if [ -z "$BOB_TXID" ]; then print_error "No se pudo enviar a Bob"; exit 1; fi
    print_success "TXID Bob: $BOB_TXID"
    print_info "Confirmando transacciones..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null
    print_success "Financiamiento inicial completado"
}

# Función para extraer descriptores de wallets
extract_wallet_descriptors() {
    print_section "EXTRAYENDO DESCRIPTORES DE WALLETS"
    
    # Extraer descriptores externos (receiving)
    EXT_XPUB_ALICE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listdescriptors | \
        jq -r '.descriptors[] | select(.desc | contains("/0/*") and startswith("wpkh")) | .desc' | \
        grep -Po '(?<=\().*(?=\))')
    
    EXT_XPUB_BOB=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listdescriptors | \
        jq -r '.descriptors[] | select(.desc | contains("/0/*") and startswith("wpkh")) | .desc' | \
        grep -Po '(?<=\().*(?=\))')
    
    # Extraer descriptores internos (change)
    INT_XPUB_ALICE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listdescriptors | \
        jq -r '.descriptors[] | select(.desc | contains("/1/*") and startswith("wpkh")) | .desc' | \
        grep -Po '(?<=\().*(?=\))')
    
    INT_XPUB_BOB=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listdescriptors | \
        jq -r '.descriptors[] | select(.desc | contains("/1/*") and startswith("wpkh")) | .desc' | \
        grep -Po '(?<=\().*(?=\))')
    
    print_success "Descriptores extraídos exitosamente"
    print_info "Alice External: ${EXT_XPUB_ALICE:0:50}..."
    print_info "Bob External: ${EXT_XPUB_BOB:0:50}..."
}

# Función para crear wallet multisig
create_multisig_wallet() {
    print_section "CREANDO WALLET MULTISIG 2-DE-2"
    
    # Crear descriptores multisig usando la función wsh(multi(2,...))
    EXT_MULTISIG_DESC_RAW="wsh(multi(2,$EXT_XPUB_ALICE,$EXT_XPUB_BOB))"
    INT_MULTISIG_DESC_RAW="wsh(multi(2,$INT_XPUB_ALICE,$INT_XPUB_BOB))"
    
    # Obtener descriptores con checksums
    EXT_MULTISIG_DESC=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getdescriptorinfo "$EXT_MULTISIG_DESC_RAW" | jq -r '.descriptor')
    INT_MULTISIG_DESC=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getdescriptorinfo "$INT_MULTISIG_DESC_RAW" | jq -r '.descriptor')
    
    # Crear wallet multisig (watch-only, disable private keys)
    print_info "Creando wallet multisig watch-only..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MULTISIG_WALLET" true true > /dev/null
    
    # Importar descriptores
    print_info "Importando descriptores multisig..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" importdescriptors \
        "[{\"desc\":\"$EXT_MULTISIG_DESC\",\"active\":true,\"internal\":false,\"timestamp\":0},{\"desc\":\"$INT_MULTISIG_DESC\",\"active\":true,\"internal\":true,\"timestamp\":0}]" > /dev/null
    
    # Generar dirección multisig
    MULTISIG_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getnewaddress)
    MULTISIG_DESC="$EXT_MULTISIG_DESC"
    
    print_success "Wallet multisig creado exitosamente"
    print_success "Dirección multisig: $MULTISIG_ADDR"
}

# Función para financiar dirección multisig
fund_multisig_address() {
    print_section "FINANCIANDO DIRECCIÓN MULTISIG"
    # Obtener UTXOs de Alice y Bob
    ALICE_UTXOS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listunspent)
    BOB_UTXOS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listunspent)
    # Validar UTXOs
    ALICE_TXID_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].txid')
    ALICE_VOUT_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].vout')
    ALICE_AMOUNT_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].amount')
    BOB_TXID_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].txid')
    BOB_VOUT_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].vout')
    BOB_AMOUNT_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].amount')
    if [ "$ALICE_TXID_INPUT" = "null" ] || [ -z "$ALICE_TXID_INPUT" ] || [ "$BOB_TXID_INPUT" = "null" ] || [ -z "$BOB_TXID_INPUT" ]; then
        print_error "No se encontraron UTXOs válidos para Alice o Bob. ¿Ya ejecutaste el financiamiento inicial? Si tienes datos corruptos, ejecuta: bash $0 limpiar"
        exit 1
    fi
    print_info "UTXO Alice: $ALICE_AMOUNT_INPUT BTC"
    print_info "UTXO Bob: $BOB_AMOUNT_INPUT BTC"
    # Calcular cambio (10 BTC cada uno al multisig + fees)
    ALICE_CHANGE=$(echo "$ALICE_AMOUNT_INPUT - 10 - 0.001" | bc -l)
    BOB_CHANGE=$(echo "$BOB_AMOUNT_INPUT - 10 - 0.001" | bc -l)
    print_info "Creando PSBT para financiar multisig con 20 BTC (10 de cada uno)..."
    # Crear PSBT
    FUNDING_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createpsbt \
        "[{\"txid\":\"$ALICE_TXID_INPUT\",\"vout\":$ALICE_VOUT_INPUT},{\"txid\":\"$BOB_TXID_INPUT\",\"vout\":$BOB_VOUT_INPUT}]" \
        "{\"$MULTISIG_ADDR\":20,\"$ALICE_ADDR\":$ALICE_CHANGE,\"$BOB_ADDR\":$BOB_CHANGE}")
    # Firmar por Alice
    print_info "Firmando PSBT por Alice..."
    ALICE_SIGNED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" walletprocesspsbt "$FUNDING_PSBT" | jq -r '.psbt')
    # Firmar por Bob
    print_info "Firmando PSBT por Bob..."
    BOB_SIGNED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" walletprocesspsbt "$ALICE_SIGNED_PSBT" | jq -r '.psbt')
    # Finalizar y transmitir
    print_info "Finalizando transacción..."
    FINAL_TX=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" finalizepsbt "$BOB_SIGNED_PSBT" | jq -r '.hex')
    FUNDING_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$FINAL_TX")
    print_success "Transacción de financiamiento enviada: $FUNDING_TXID"
    # Confirmar transacción
    print_info "Confirmando transacción..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" rescanblockchain 0 > /dev/null
    print_success "Financiamiento multisig completado"
}

# Función para mostrar saldos
show_balances() {
    local title="$1"
    print_section "$title"
    
    local alice_balance=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getbalances | jq -r '.mine.trusted')
    local bob_balance=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" getbalances | jq -r '.mine.trusted')
    local multisig_balance=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getbalances | jq -r '.mine.trusted')
    
    echo -e "${GREEN}Alice:${NC} $alice_balance BTC"
    echo -e "${GREEN}Bob:${NC} $bob_balance BTC"
    echo -e "${GREEN}Multisig:${NC} $multisig_balance BTC"
}

# Función para liquidar multisig
liquidate_multisig() {
    print_section "LIQUIDANDO MULTISIG"
    
    # Obtener UTXO multisig
    MULTI_UTXO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" listunspent | jq '.[0]')
    MS_TXID=$(echo "$MULTI_UTXO" | jq -r '.txid')
    MS_VOUT=$(echo "$MULTI_UTXO" | jq -r '.vout')
    MS_AMOUNT=$(echo "$MULTI_UTXO" | jq -r '.amount')
    
    # Verificar si encontramos el UTXO
    if [ "$MS_TXID" = "null" ] || [ -z "$MS_TXID" ]; then
        print_warning "No se encontró UTXO en wallet multisig, buscando en transacción de financiamiento..."
        TX_INFO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getrawtransaction "$FUNDING_TXID" true)
        MS_VOUT=$(echo "$TX_INFO" | jq -r '.vout[] | select(.scriptPubKey.address == "'$MULTISIG_ADDR'") | .n')
        MS_AMOUNT=$(echo "$TX_INFO" | jq -r '.vout[] | select(.scriptPubKey.address == "'$MULTISIG_ADDR'") | .value')
        MS_TXID="$FUNDING_TXID"
    fi
    
    print_info "UTXO Multisig: $MS_AMOUNT BTC en $MS_TXID:$MS_VOUT"
    
    # Generar direcciones para la liquidación
    MULTISIG_CHANGE_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getnewaddress)
    ALICE_NEW_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getnewaddress "Desde Multisig")
    
    print_info "Creando PSBT de liquidación (3 BTC a Alice, resto como cambio)..."
    
    # Crear PSBT de liquidación
    LIQUIDATION_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" walletcreatefundedpsbt \
        "[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT}]" \
        "{\"$ALICE_NEW_ADDR\":3,\"$MULTISIG_CHANGE_ADDR\":16.9999}" \
        0 '{"includeWatching":true}' | jq -r '.psbt')
    
    # Importar descriptores en wallets de Alice y Bob para firmar
    print_info "Importando descriptores multisig en wallets individuales..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" importdescriptors \
        "[{\"desc\":\"$MULTISIG_DESC\",\"active\":false,\"internal\":false,\"timestamp\":0}]" > /dev/null 2>&1 || true
    
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" importdescriptors \
        "[{\"desc\":\"$MULTISIG_DESC\",\"active\":false,\"internal\":false,\"timestamp\":0}]" > /dev/null 2>&1 || true
    
    # Firmar por Alice
    print_info "Firmando PSBT de liquidación por Alice..."
    ALICE_LIQUID_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" walletprocesspsbt "$LIQUIDATION_PSBT")
    ALICE_LIQUID_PSBT=$(echo "$ALICE_LIQUID_RESULT" | jq -r '.psbt')
    
    # Firmar por Bob
    print_info "Firmando PSBT de liquidación por Bob..."
    BOB_LIQUID_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" walletprocesspsbt "$LIQUIDATION_PSBT")
    BOB_LIQUID_PSBT=$(echo "$BOB_LIQUID_RESULT" | jq -r '.psbt')
    
    # Combinar firmas
    print_info "Combinando firmas..."
    COMBINED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" combinepsbt "[\"$ALICE_LIQUID_PSBT\",\"$BOB_LIQUID_PSBT\"]")
    
    # Finalizar transacción
    print_info "Finalizando transacción de liquidación..."
    FINAL_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" finalizepsbt "$COMBINED_PSBT")
    PSBT_COMPLETE=$(echo "$FINAL_RESULT" | jq -r '.complete')
    
    if [ "$PSBT_COMPLETE" = "true" ]; then
        FINAL_LIQUID_TX=$(echo "$FINAL_RESULT" | jq -r '.hex')
        print_success "PSBT completada exitosamente"
    else
        print_error "No se pudo completar la PSBT de liquidación"
        exit 1
    fi
    
    # Transmitir transacción
    LIQUIDATION_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$FINAL_LIQUID_TX")
    print_success "Transacción de liquidación enviada: $LIQUIDATION_TXID"
    
    # Confirmar transacción
    print_info "Confirmando transacción de liquidación..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null
    
    print_success "Liquidación multisig completada"
}

# =========================== FUNCIÓN PRINCIPAL ===========================

main() {
    full_cleanup
    command -v bitcoin-cli >/dev/null 2>&1 || { print_error "bitcoin-cli no está instalado"; exit 1; }
    command -v bitcoind >/dev/null 2>&1 || { print_error "bitcoind no está instalado"; exit 1; }
    command -v jq >/dev/null 2>&1 || { print_error "jq no está instalado"; exit 1; }
    command -v bc >/dev/null 2>&1 || { print_error "bc no está instalado"; exit 1; }

    print_section "INICIANDO SIMULACIÓN MULTISIG BITCOIN"

    print_info "Configurando y arrancando bitcoind..."
    setup_bitcoin_core || { print_error "Fallo al configurar Bitcoin Core"; exit 1; }

    print_info "Creando o cargando wallets..."
    create_wallets || { print_error "Fallo al crear/cargar wallets"; exit 1; }

    print_info "Generando direcciones iniciales..."
    generate_initial_addresses || { print_error "Fallo al generar direcciones"; exit 1; }

    print_info "Financiando wallets..."
    fund_initial_wallets || { print_error "Fallo al financiar wallets"; exit 1; }

    print_info "Extrayendo descriptores..."
    extract_wallet_descriptors || { print_error "Fallo al extraer descriptores"; exit 1; }

    print_info "Creando wallet multisig..."
    create_multisig_wallet || { print_error "Fallo al crear wallet multisig"; exit 1; }

    print_info "Financiando dirección multisig..."
    fund_multisig_address || { print_error "Fallo al financiar multisig"; exit 1; }

    show_balances "SALDOS DESPUÉS DEL FINANCIAMIENTO"

    print_info "Ejecutando liquidación multisig..."
    liquidate_multisig || { print_error "Fallo al liquidar multisig"; exit 1; }

    show_balances "SALDOS FINALES"

    print_section "SIMULACIÓN COMPLETADA EXITOSAMENTE"
    print_success "Todas las operaciones multisig se ejecutaron correctamente"
    print_info "El script se detendrá y limpiará automáticamente..."
    cleanup
}

# Ejecutar función principal
main "$@"