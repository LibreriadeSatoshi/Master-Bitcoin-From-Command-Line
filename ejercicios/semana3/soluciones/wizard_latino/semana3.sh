#!/bin/bash

# =============================================================================
# SEMANA 3 - Bitcoin Core: Demostración Transacciones Multisig
# =============================================================================
# Ejercicio del taller "Master Bitcoin From Command Line"
# Librería de Satoshi
# Autor: wizard_latino
#
# Enlace al ejercicio: https://github.com/LibreriadeSatoshi/Master-Bitcoin-From-Command-Line/blob/main/ejercicios/semana3/ejercicio.md
#
# DESCRIPCIÓN:
# Este ejercicio demuestra el mecanismo de transacciones multisig 2-de-2
# entre Alice y Bob usando una arquitectura modular educativa.
# 
# OBJETIVOS DEL EJERCICIO:
# 1. Demostrar flujos de trabajo de billeteras Bitcoin usando bitcoin-cli
# 2. Ilustrar el mecanismo de direcciones multisig 2-de-2
# 3. Mostrar creación y firma de PSBT (Partially Signed Bitcoin Transactions)
# 4. Implementar fondeo y gasto de direcciones multisig

# Colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Variables globales
BITCOIN_TOOLS_DIR="${HOME}/bitcoin-tools"
BITCOIN_BIN_DIR="${BITCOIN_TOOLS_DIR}/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Función para imprimir líneas separadoras
print_separator() {
    echo -e "${CYAN}========================================${NC}"
}

# Función para mostrar ayuda
show_help() {
    echo -e "${CYAN}Uso: $0 [opciones]${NC}"
    echo -e "${YELLOW}Opciones:${NC}"
    echo -e "  --clean        Limpiar entorno Bitcoin antes de ejecutar"
    echo -e "  --clean-only   Solo limpiar entorno (no ejecutar ejercicio)"
    echo -e "  -h, --help     Mostrar esta ayuda"
    echo ""
    echo -e "${YELLOW}Ejemplos:${NC}"
    echo -e "  $0              # Ejecutar ejercicio normal"
    echo -e "  $0 --clean      # Limpiar y ejecutar ejercicio"
    echo -e "  $0 --clean-only # Solo limpiar entorno"
}

# Función para manejar errores
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Verificar que estamos en el directorio correcto
check_directory() {
    local current_dir=$(basename "$PWD")
    if [ "$current_dir" != "semana3" ]; then
        echo -e "${RED}Error: Este script debe ejecutarse desde el directorio semana3${NC}"
        echo -e "${YELLOW}Por favor, navega al directorio correcto:${NC}"
        echo -e "${CYAN}cd /ruta/a/bitcoin-scripts/semana3${NC}"
        exit 1
    fi
}

# Cargar módulos
load_modules() {
    echo -e "${YELLOW}Cargando módulos...${NC}"
    source "${SCRIPT_DIR}/setup_bitcoin.sh"
    source "${SCRIPT_DIR}/manage_wallets.sh"
    # Cargar el módulo de demostración multisig
    source "${SCRIPT_DIR}/multisig_demo.sh"
    source "${SCRIPT_DIR}/clean_bitcoin.sh"
    echo -e "${GREEN}✓ Módulos cargados correctamente${NC}"
}

# Ejercicio multisig
demonstrate_multisig_concepts() {
    print_separator
    echo -e "${CYAN}EJERCICIO MULTISIG${NC}"
    print_separator
    
    echo -e "${YELLOW}1. Obteniendo claves públicas de Alice y Bob...${NC}"
    
    # Crear direcciones legacy para obtener claves públicas
    local alice_legacy=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "multisig_demo" "legacy")
    local bob_legacy=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Bob getnewaddress "multisig_demo" "legacy")
    
    echo -e "${GREEN}Dirección legacy Alice: ${alice_legacy}${NC}"
    echo -e "${GREEN}Dirección legacy Bob: ${bob_legacy}${NC}"
    
    # Obtener claves públicas
    local alice_info=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Alice getaddressinfo "${alice_legacy}")
    local bob_info=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Bob getaddressinfo "${bob_legacy}")
    
    local alice_pubkey=$(echo "$alice_info" | jq -r '.pubkey')
    local bob_pubkey=$(echo "$bob_info" | jq -r '.pubkey')
    
    echo -e "${GREEN}✓ Clave pública Alice: ${alice_pubkey}${NC}"
    echo -e "${GREEN}✓ Clave pública Bob: ${bob_pubkey}${NC}"
    
    echo -e "${YELLOW}2. Creando dirección multisig 2-de-2...${NC}"
    
    local multisig_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createmultisig 2 "[\"${alice_pubkey}\",\"${bob_pubkey}\"]")
    local multisig_address=$(echo "$multisig_result" | jq -r '.address')
    local redeem_script=$(echo "$multisig_result" | jq -r '.redeemScript')
    local descriptor=$(echo "$multisig_result" | jq -r '.descriptor')
    
    echo -e "${GREEN}✓ Dirección multisig: ${multisig_address}${NC}"
    echo -e "${GREEN}✓ Redeem Script: ${redeem_script}${NC}"
    echo -e "${GREEN}✓ Descriptor: ${descriptor}${NC}"
    
    echo -e "${YELLOW}3. Enviando fondos al multisig...${NC}"
    
    # Alice y Bob envían fondos al multisig
    local alice_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Alice sendtoaddress "${multisig_address}" 5)
    local bob_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Bob sendtoaddress "${multisig_address}" 5)
    
    echo -e "${GREEN}✓ TX Alice → Multisig: ${alice_tx}${NC}"
    echo -e "${GREEN}✓ TX Bob → Multisig: ${bob_tx}${NC}"
    
    # Confirmar transacciones
    echo -e "${YELLOW}Confirmando transacciones...${NC}"
    ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 6 "${MINER_ADDRESS}" >/dev/null
    
    echo -e "${YELLOW}4. Verificando saldo del multisig...${NC}"
    
    # Usar scantxoutset para verificar saldo
    local scan_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest scantxoutset start "[\"addr(${multisig_address})\"]")
    local multisig_balance=$(echo "$scan_result" | jq -r '.total_amount')
    local utxo_count=$(echo "$scan_result" | jq -r '.unspents | length')
    
    echo -e "${GREEN}✓ Saldo total multisig: ${multisig_balance} BTC${NC}"
    echo -e "${GREEN}✓ UTXOs encontrados: ${utxo_count}${NC}"
    
    # Mostrar detalles de UTXOs
    echo -e "${YELLOW}Detalles de UTXOs en multisig:${NC}"
    echo "$scan_result" | jq -r '.unspents[] | "  - \(.txid):\(.vout) = \(.amount) BTC"'
    
    echo -e "${YELLOW}5. Creando transacción de ejemplo...${NC}"
    
    # Crear direcciones de destino
    local alice_dest=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "from_multisig")
    local bob_dest=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Bob getnewaddress "from_multisig")
    
    echo -e "${GREEN}Dirección destino Alice: ${alice_dest}${NC}"
    echo -e "${GREEN}Dirección destino Bob: ${bob_dest}${NC}"
    
    # Obtener primer UTXO
    local first_utxo=$(echo "$scan_result" | jq -r '.unspents[0]')
    local utxo_txid=$(echo "$first_utxo" | jq -r '.txid')
    local utxo_vout=$(echo "$first_utxo" | jq -r '.vout')
    local utxo_amount=$(echo "$first_utxo" | jq -r '.amount')
    
    echo -e "${YELLOW}Usando UTXO: ${utxo_txid}:${utxo_vout} (${utxo_amount} BTC)${NC}"
    
    # Crear transacción raw
    local raw_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createrawtransaction \
        "[{\"txid\":\"${utxo_txid}\",\"vout\":${utxo_vout}}]" \
        "{\"${alice_dest}\":2.4999,\"${bob_dest}\":2.4999}")
    
    echo -e "${GREEN}✓ Transacción raw creada${NC}"
    echo -e "${CYAN}Hex: ${raw_tx:0:80}...${NC}"
    
    # Crear PSBT
    local psbt=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest converttopsbt "$raw_tx")
    echo -e "${GREEN}✓ PSBT creado${NC}"
    echo -e "${CYAN}PSBT: ${psbt:0:80}...${NC}"
    
    # Actualizar PSBT
    local updated_psbt=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest utxoupdatepsbt "$psbt")
    echo -e "${GREEN}✓ PSBT actualizado con información de UTXOs${NC}"
    
    echo -e "${YELLOW}6. Intentando firmar PSBT...${NC}"
    
    # Intentar firma con wallets (limitación de descriptors)
    echo -e "${CYAN}Intentando firma con wallet Alice...${NC}"
    local alice_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt "$updated_psbt" 2>&1 || echo "FAILED")
    
    if [[ "$alice_result" == *"FAILED"* ]] || [[ "$alice_result" == *"not available"* ]]; then
        echo -e "${YELLOW}⚠ Alice no puede firmar - clave no disponible en wallet${NC}"
    else
        echo -e "${GREEN}Alice firmó exitosamente${NC}"
    fi
    
    echo -e "${CYAN}Intentando firma con wallet Bob...${NC}"
    local bob_result=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt "$updated_psbt" 2>&1 || echo "FAILED")
    
    if [[ "$bob_result" == *"FAILED"* ]] || [[ "$bob_result" == *"not available"* ]]; then
        echo -e "${YELLOW}⚠ Bob no puede firmar - clave no disponible en wallet${NC}"
    else
        echo -e "${GREEN}Bob firmó exitosamente${NC}"
    fi
    
    print_separator
    echo -e "${CYAN}RESUMEN DEL EJERCICIO${NC}"
    print_separator
    echo -e "${GREEN}✓ Multisig 2-de-2 creado exitosamente${NC}"
    echo -e "${GREEN}✓ Direcciones y claves públicas obtenidas${NC}"
    echo -e "${GREEN}✓ Fondos enviados al multisig (10 BTC total)${NC}"
    echo -e "${GREEN}✓ UTXOs rastreados con scantxoutset${NC}"
    echo -e "${GREEN}✓ Transacción raw y PSBT generados${NC}"
    
    print_separator
    echo -e "${YELLOW}NOTAS TÉCNICAS:${NC}"
    echo -e "• Bitcoin Core v29 usa descriptor wallets por defecto"
    echo -e "• Multisig requiere importar claves para firma completa"
    echo -e "• scantxoutset permite rastrear UTXOs externos"
    echo -e "• PSBT facilita transacciones parcialmente firmadas"
}

# Función para mostrar instrucciones de re-ejecución
show_reexecution_info() {
    print_separator
    echo -e "${CYAN}=== EJERCICIO SEMANA 3 COMPLETADO ===${NC}"
    echo -e "${CYAN}Arquitectura modular utilizada:${NC}"
    echo -e "  - setup_bitcoin.sh - Configuración base"
    echo -e "  - manage_wallets.sh - Gestión de billeteras"
    echo -e "  - multisig_demo.sh - Demostración Multisig con PSBT y comparación Legacy vs Descriptors"
    echo -e "  - clean_bitcoin.sh - Limpieza de entorno"
    echo -e "${YELLOW}Todos los módulos son reutilizables dentro de esta carpeta${NC}"
    
    print_separator
    echo -e "${CYAN}OPCIONES PARA VOLVER A EJECUTAR:${NC}"
    echo -e "${YELLOW}Para testing iterativo recomendado:${NC}"
    echo -e "  - ./clean_bitcoin.sh -y && ./semana3.sh  # Limpiar solo datos + ejecutar (RAPIDO)"
    echo -e "  - ./semana3.sh                           # Ejecutar sin limpiar"
    echo -e "${YELLOW}Para empezar desde cero:${NC}"
    echo -e "  - ./clean_bitcoin.sh -y -f && ./semana3.sh  # Limpieza completa + ejecutar"
    echo -e "  - ./semana3.sh --clean                      # Limpieza completa + ejecutar"
    echo -e "${YELLOW}Opciones de limpieza:${NC}"
    echo -e "  - ./clean_bitcoin.sh --help                 # Ver todas las opciones"
    print_separator
}

# Función principal
main() {
    local clean_before=false
    local clean_only=false
    
    # Procesar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_before=true
                shift
                ;;
            --clean-only)
                clean_only=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Opción desconocida: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_separator
    echo -e "${CYAN}=== SEMANA 3: Transacciones Multisig Demonstration ===${NC}"
    echo -e "${YELLOW}Taller: Master Bitcoin From Command Line${NC}"
    echo -e "${YELLOW}Librería de Satoshi${NC}"
    print_separator
    
    check_directory
    
    # Cargar módulos
    load_modules
    
    # Ejecutar limpieza si se solicita
    if [ "$clean_before" = true ] || [ "$clean_only" = true ]; then
        print_separator
        echo -e "${CYAN}LIMPIEZA DE ENTORNO SOLICITADA${NC}"
        print_separator
        clean_bitcoin_environment true false true  # auto_confirm=true, verbose=false, full_clean=true
        
        if [ "$clean_only" = true ]; then
            echo -e "${GREEN}✓ Limpieza completada. Saliendo...${NC}"
            exit 0
        fi
    fi
    
    print_separator
    echo -e "${CYAN}FASE 1: CONFIGURACIÓN DEL ENTORNO${NC}"
    print_separator
    
    # Configurar Bitcoin Core
    setup_bitcoin_core
    
    print_separator
    echo -e "${CYAN}FASE 2: PREPARACIÓN DE BILLETERAS${NC}"
    print_separator
    
    # Configurar billeteras
    setup_wallet_environment
    
    print_separator
    echo -e "${CYAN}FASE 3: DEMOSTRACIÓN MULTISIG${NC}"
    print_separator
    
    # Ejecutar demostración multisig
    echo -e "${YELLOW}Ejecutando demostración mejorada con comparación legacy vs descriptors...${NC}"
    run_multisig_demo
    
    # Mostrar instrucciones de re-ejecución
    show_reexecution_info
}

# Manejo de señales para limpieza
trap 'echo -e "\n${RED}Script interrumpido${NC}"; exit 1' INT TERM

# Ejecutar función principal
main "$@"