#!/bin/bash

# =============================================================================
# MÓDULO: Gestión de Billeteras
# =============================================================================
# Taller: Master Bitcoin From Command Line
# Librería de Satoshi
# Autor: wizard_latino
#
# Descripción: Módulo para manejo de billeteras Bitcoin
# - Crear/cargar billeteras Miner, Alice y Bob
# - Fondear billeteras con cantidad específica
# - Generar direcciones y claves públicas para multisig
# Uso: source manage_wallets.sh

# Variables del módulo
MINER_WALLET="Miner"
ALICE_WALLET="Alice"
BOB_WALLET="Bob"

# Función para verificar o crear billeteras
setup_wallets() {
    print_separator
    echo -e "${CYAN}Configurando billeteras para ejercicio multisig${NC}"
    
    # Crear billetera Miner
    echo -e "${YELLOW}Configurando billetera Miner...${NC}"
    if ! ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets | grep -q "\"${MINER_WALLET}\""; then
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createwallet "${MINER_WALLET}" false false "" false true true false >/dev/null 2>&1
        echo -e "${GREEN}✓ Billetera ${MINER_WALLET} creada${NC}"
    else
        echo -e "${GREEN}✓ Billetera ${MINER_WALLET} ya existe${NC}"
    fi
    
    # Crear billetera Alice
    echo -e "${YELLOW}Configurando billetera Alice...${NC}"
    if ! ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets | grep -q "\"${ALICE_WALLET}\""; then
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createwallet "${ALICE_WALLET}" false false "" false true true false >/dev/null 2>&1
        echo -e "${GREEN}✓ Billetera ${ALICE_WALLET} creada${NC}"
    else
        echo -e "${GREEN}✓ Billetera ${ALICE_WALLET} ya existe${NC}"
    fi
    
    # Crear billetera Bob
    echo -e "${YELLOW}Configurando billetera Bob...${NC}"
    if ! ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets | grep -q "\"${BOB_WALLET}\""; then
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createwallet "${BOB_WALLET}" false false "" false true true false >/dev/null 2>&1
        echo -e "${GREEN}✓ Billetera ${BOB_WALLET} creada${NC}"
    else
        echo -e "${GREEN}✓ Billetera ${BOB_WALLET} ya existe${NC}"
    fi
    
    # Verificar que las wallets están cargadas
    local loaded_wallets=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets)
    echo -e "${CYAN}Wallets cargadas: ${loaded_wallets}${NC}"
    
    echo -e "${GREEN}✓ Todas las billeteras configuradas${NC}"
}

# Función para fondear billetera Miner
fund_miner_wallet() {
    print_separator
    echo -e "${CYAN}Fondeando billetera Miner${NC}"
    
    # Generar dirección para minado
    local miner_address=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getnewaddress "Mining Reward")
    MINER_ADDRESS="$miner_address"
    echo -e "${GREEN}Dirección Miner: ${miner_address}${NC}"
    
    # Verificar saldo actual
    local current_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    echo -e "${YELLOW}Saldo actual Miner: ${current_balance} BTC${NC}"
    
    # Si no tiene suficiente saldo, minar bloques
    if (( $(echo "$current_balance < 100" | bc -l) )); then
        echo -e "${YELLOW}Minando bloques iniciales para obtener fondos...${NC}"
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} generatetoaddress 110 "${miner_address}" > /dev/null
        current_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    fi
    
    echo -e "${GREEN}✓ Saldo Miner: ${current_balance} BTC${NC}"
}

# Función para fondear Alice y Bob
fund_alice_and_bob() {
    print_separator
    echo -e "${CYAN}Fondeando billeteras Alice y Bob${NC}"
    
    # Generar direcciones
    ALICE_ADDRESS=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${ALICE_WALLET} getnewaddress "Fondos Alice")
    BOB_ADDRESS=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${BOB_WALLET} getnewaddress "Fondos Bob")
    
    echo -e "${GREEN}Dirección Alice: ${ALICE_ADDRESS}${NC}"
    echo -e "${GREEN}Dirección Bob: ${BOB_ADDRESS}${NC}"
    
    # Enviar 15 BTC a cada uno (para tener suficiente para el ejercicio + fees)
    echo -e "${YELLOW}Enviando fondos a Alice...${NC}"
    local alice_txid=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} sendtoaddress "${ALICE_ADDRESS}" 15)
    echo -e "${GREEN}✓ TX Alice: ${alice_txid}${NC}"
    
    echo -e "${YELLOW}Enviando fondos a Bob...${NC}"
    local bob_txid=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} sendtoaddress "${BOB_ADDRESS}" 15)
    echo -e "${GREEN}✓ TX Bob: ${bob_txid}${NC}"
    
    # Confirmar transacciones
    echo -e "${YELLOW}Confirmando transacciones...${NC}"
    ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} generatetoaddress 6 "${MINER_ADDRESS}" > /dev/null
    
    # Verificar saldos
    local alice_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${ALICE_WALLET} getbalance)
    local bob_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${BOB_WALLET} getbalance)
    
    echo -e "${GREEN}✓ Saldo Alice: ${alice_balance} BTC${NC}"
    echo -e "${GREEN}✓ Saldo Bob: ${bob_balance} BTC${NC}"
}

# Función para obtener claves públicas para multisig
get_public_keys() {
    print_separator
    echo -e "${CYAN}Obteniendo claves públicas para multisig${NC}"
    
    # Generar direcciones legacy para obtener claves públicas
    echo -e "${YELLOW}Generando direcciones legacy...${NC}"
    
    # Generar nuevas direcciones y obtener sus claves públicas
    ALICE_MULTISIG_ADDRESS=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${ALICE_WALLET} getnewaddress "Multisig" "legacy")
    BOB_MULTISIG_ADDRESS=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${BOB_WALLET} getnewaddress "Multisig" "legacy")
    
    # Obtener claves públicas de las direcciones
    local alice_address_info=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${ALICE_WALLET} getaddressinfo "${ALICE_MULTISIG_ADDRESS}")
    local bob_address_info=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${BOB_WALLET} getaddressinfo "${BOB_MULTISIG_ADDRESS}")
    
    # Extraer claves públicas
    ALICE_PUBKEY=$(echo "$alice_address_info" | jq -r '.pubkey')
    BOB_PUBKEY=$(echo "$bob_address_info" | jq -r '.pubkey')
    
    echo -e "${GREEN}✓ Clave pública Alice: ${ALICE_PUBKEY}${NC}"
    echo -e "${GREEN}✓ Clave pública Bob: ${BOB_PUBKEY}${NC}"
    
    # Verificar que las claves no están vacías
    if [ -z "$ALICE_PUBKEY" ] || [ "$ALICE_PUBKEY" = "null" ]; then
        echo -e "${RED}Error: No se pudo obtener la clave pública de Alice${NC}"
        return 1
    fi
    
    if [ -z "$BOB_PUBKEY" ] || [ "$BOB_PUBKEY" = "null" ]; then
        echo -e "${RED}Error: No se pudo obtener la clave pública de Bob${NC}"
        return 1
    fi
}

# Función para mostrar saldos actuales
show_wallet_balances() {
    print_separator
    echo -e "${CYAN}Saldos actuales${NC}"
    
    local miner_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    local alice_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${ALICE_WALLET} getbalance)
    local bob_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${BOB_WALLET} getbalance)
    
    echo -e "${GREEN}Miner: ${miner_balance} BTC${NC}"
    echo -e "${GREEN}Alice: ${alice_balance} BTC${NC}"
    echo -e "${GREEN}Bob: ${bob_balance} BTC${NC}"
}

# Función principal del módulo
setup_wallet_environment() {
    setup_wallets
    fund_miner_wallet
    fund_alice_and_bob
    get_public_keys
}

# Si se ejecuta directamente, ejecutar setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Incluir funciones necesarias
    print_separator() {
        echo -e "${CYAN}========================================${NC}"
    }
    
    # Colores
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    
    # Paths
    BITCOIN_BIN_DIR="${HOME}/bitcoin-tools/bin"
    
    setup_wallet_environment
    show_wallet_balances
fi