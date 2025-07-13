#!/bin/bash

# =============================================================================
# MÓDULO: Gestión de Billeteras
# =============================================================================
# Taller: Master Bitcoin From Command Line
# Librería de Satoshi
# Autor: wizard_latino
#
# Descripción: Módulo para manejo de billeteras Bitcoin
# - Crear/cargar billeteras Miner y Trader
# - Fondear billeteras con cantidad específica
# - Generar direcciones y verificar saldos
# Uso: source manage_wallets.sh

# Variables del módulo
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

# Función para verificar o crear billeteras
setup_wallets() {
    print_separator
    echo -e "${CYAN}Paso 4: Verificar billeteras Miner y Trader${NC}"
    echo -e "${YELLOW}Se espera: Confirmar o crear billeteras necesarias para el ejercicio${NC}"
    
    # Verificar billetera Miner
    print_separator
    echo -e "${CYAN}Paso 4.1: Configurar billetera Miner${NC}"
    echo -e "${YELLOW}Se espera: Billetera Miner disponible para minado y transacciones${NC}"
    
    local miner_exists=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets 2>/dev/null | grep -c "\"${MINER_WALLET}\"")
    if [ "$miner_exists" -eq 0 ]; then
        echo -e "${YELLOW}Creando billetera ${MINER_WALLET}...${NC}"
        local create_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createwallet "${MINER_WALLET}" 2>&1)
        if [[ $create_result == *"Database already exists"* ]]; then
            echo -e "${YELLOW}Cargando billetera existente ${MINER_WALLET}...${NC}"
            ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest loadwallet "${MINER_WALLET}" 2>/dev/null || true
        elif [[ $create_result == *"error"* ]]; then
            echo -e "${RED}Error configurando billetera Miner: $create_result${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Billetera ${MINER_WALLET} creada y cargada${NC}"
    else
        echo -e "${GREEN}✓ Billetera ${MINER_WALLET} ya está cargada${NC}"
    fi
    
    # Verificar billetera Trader
    print_separator
    echo -e "${CYAN}Paso 4.2: Configurar billetera Trader${NC}"
    echo -e "${YELLOW}Se espera: Billetera Trader disponible para recibir transacciones${NC}"
    
    local trader_exists=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest listwallets 2>/dev/null | grep -c "\"${TRADER_WALLET}\"")
    if [ "$trader_exists" -eq 0 ]; then
        echo -e "${YELLOW}Creando billetera ${TRADER_WALLET}...${NC}"
        local create_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createwallet "${TRADER_WALLET}" 2>&1)
        if [[ $create_result == *"Database already exists"* ]]; then
            echo -e "${YELLOW}Cargando billetera existente ${TRADER_WALLET}...${NC}"
            ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest loadwallet "${TRADER_WALLET}" 2>/dev/null || true
        elif [[ $create_result == *"error"* ]]; then
            echo -e "${RED}Error configurando billetera Trader: $create_result${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Billetera ${TRADER_WALLET} creada y cargada${NC}"
    else
        echo -e "${GREEN}✓ Billetera ${TRADER_WALLET} ya está cargada${NC}"
    fi
    
    echo -e "${GREEN}Billeteras Miner y Trader disponibles${NC}"
}

# Función para fondear billetera Miner
fund_miner_wallet() {
    local target_balance=${1:-150}  # Default 150 BTC
    
    print_separator
    echo -e "${CYAN}Paso 5: Fondear billetera Miner con ${target_balance} BTC${NC}"
    echo -e "${YELLOW}Se espera: Minar bloques hasta alcanzar exactamente ${target_balance} BTC${NC}"
    
    # Generar dirección para minado
    print_separator
    echo -e "${CYAN}Paso 5.1: Generar dirección de minado${NC}"
    echo -e "${YELLOW}Se espera: Nueva dirección Bitcoin para recibir recompensas de minado${NC}"
    
    local miner_address=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getnewaddress "Recompensa de Minería") || { echo -e "${RED}Error: No se pudo generar dirección de Miner${NC}"; exit 1; }
    echo -e "${GREEN}Dirección de minado: ${miner_address}${NC}"
    
    # Verificar saldo actual
    print_separator
    echo -e "${CYAN}Paso 5.2: Verificar saldo actual y minar bloques${NC}"
    echo -e "${YELLOW}Se espera: Minado progresivo hasta alcanzar ${target_balance} BTC exactos${NC}"
    
    local current_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    local current_balance_int=$(echo "$current_balance" | cut -d. -f1)
    
    echo -e "${YELLOW}Saldo inicial: ${current_balance} BTC${NC}"
    echo -e "${YELLOW}Objetivo: ${target_balance} BTC${NC}"
    
    # Verificar si ya tiene suficiente saldo
    if [ "$current_balance_int" -ge "$target_balance" ]; then
        echo -e "${GREEN}✓ Ya tienes suficiente saldo: ${current_balance} BTC${NC}"
        echo -e "${CYAN}No es necesario minar más bloques${NC}"
        MINER_ADDRESS="$miner_address"
        return 0
    fi
    
    # Minar hasta alcanzar el objetivo
    local maturation_blocks=100
    local reward_per_block=50
    local current_block_height=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getblockcount)
    local spendable_blocks=$((current_block_height > maturation_blocks ? current_block_height - maturation_blocks : 0))
    local blocks_needed_for_rewards=$(((target_balance - current_balance_int + reward_per_block - 1) / reward_per_block))
    local total_blocks_needed=$((maturation_blocks + blocks_needed_for_rewards))
    
    if [ "$current_block_height" -lt "$maturation_blocks" ]; then
        echo -e "${CYAN}Necesitas minar ${total_blocks_needed} bloques total (${maturation_blocks} para maduración + ${blocks_needed_for_rewards} para recompensas)${NC}"
    else
        echo -e "${CYAN}Necesitas aproximadamente ${blocks_needed_for_rewards} bloques más para obtener ${target_balance} BTC${NC}"
    fi
    
    local blocks_mined=0
    local last_printed_block=0
    while [ "$current_balance_int" -lt "$target_balance" ]; do
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} generatetoaddress 1 "${miner_address}" > /dev/null || { echo -e "${RED}Error al minar bloque${NC}"; exit 1; }
        blocks_mined=$((blocks_mined + 1))
        current_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
        current_balance_int=$(echo "$current_balance" | cut -d. -f1)
        
        # Mostrar progreso cada 10 bloques y los primeros 5 bloques
        if [ $((blocks_mined % 10)) -eq 0 ] || [ "$blocks_mined" -le 5 ]; then
            echo -e "${YELLOW}Progreso: ${blocks_mined} bloques minados | Saldo: ${current_balance} BTC${NC}"
            last_printed_block=$blocks_mined
        fi
    done
    
    # Mostrar el bloque final si no fue el último mostrado
    if [ "$blocks_mined" -ne "$last_printed_block" ]; then
        echo -e "${YELLOW}Progreso: ${blocks_mined} bloques minados | Saldo: ${current_balance} BTC${NC}"
    fi
    
    echo -e "${GREEN}✓ Proceso de minado completado${NC}"
    echo -e "${GREEN}✓ Total de bloques minados: ${blocks_mined}${NC}"
    echo -e "${GREEN}✓ Saldo final de Miner: ${current_balance} BTC${NC}"
    
    # Guardar la dirección en variable global
    MINER_ADDRESS="$miner_address"
}

# Función para generar dirección de Trader
generate_trader_address() {
    print_separator
    echo -e "${CYAN}Paso 6: Generar dirección para Trader${NC}"
    echo -e "${YELLOW}Se espera: Nueva dirección Bitcoin para recibir transacciones en ejercicio${NC}"
    
    TRADER_ADDRESS=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${TRADER_WALLET} getnewaddress "Recibido") || { echo -e "${RED}Error: No se pudo generar dirección de Trader${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Dirección Trader generada exitosamente${NC}"
    echo -e "${GREEN}Dirección: ${TRADER_ADDRESS}${NC}"
}

# Función para mostrar saldos
show_wallet_balances() {
    print_separator
    echo -e "${CYAN}Paso 7: Mostrar saldos iniciales${NC}"
    echo -e "${YELLOW}Se espera: Verificación de fondos disponibles en ambas billeteras${NC}"
    
    local miner_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    local trader_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${TRADER_WALLET} getbalance)
    
    echo -e "${GREEN}✓ Saldo Miner: ${miner_balance} BTC${NC}"
    echo -e "${GREEN}✓ Saldo Trader: ${trader_balance} BTC${NC}"
    echo -e "${GREEN}Billeteras listas para demostración RBF vs CPFP${NC}"
}

# Función principal del módulo
setup_wallet_environment() {
    setup_wallets
    fund_miner_wallet 150
    generate_trader_address
    show_wallet_balances
}