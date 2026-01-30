#!/bin/bash

# =============================================================================
# MÓDULO: Demostración Replace-By-Fee (RBF)
# =============================================================================
# Taller: Master Bitcoin From Command Line
# Librería de Satoshi
# Autor: wizard_latino
#
# Descripción: Módulo que demuestra el mecanismo RBF y su impacto en transacciones child
# - Crea transacción parent con RBF habilitado
# - Construye JSON de análisis técnico
# - Demuestra creación de transacción child
# - Ejecuta RBF y muestra impacto en transacciones dependientes
# - Análisis comparativo de técnicas de fee management
# Uso: source rbf_demo.sh

# Variables del módulo
PARENT_TXID=""
CHILD_TXID=""
REPLACEMENT_TXID=""

# Función para crear transacción parent con RBF
create_rbf_parent() {
    print_separator
    echo -e "${CYAN}Paso 8: Seleccionar UTXOs para transacción parent${NC}"
    echo -e "${YELLOW}Se espera: Encontrar exactamente 2 UTXOs de 50 BTC cada uno${NC}"
    
    # Obtener UTXOs
    local utxos=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} listunspent) || { echo -e "${RED}Error: No se pudieron obtener UTXOs${NC}"; exit 1; }
    
    # Seleccionar 2 UTXOs de 50 BTC
    local utxo1=$(echo "$utxos" | jq -r '.[] | select(.amount == 50) | "\(.txid):\(.vout)"' | head -1)
    local utxo2=$(echo "$utxos" | jq -r '.[] | select(.amount == 50) | "\(.txid):\(.vout)"' | head -2 | tail -1)
    
    if [ -z "$utxo1" ] || [ -z "$utxo2" ]; then
        echo -e "${RED}Error: No se encontraron suficientes UTXOs de 50 BTC${NC}"
        exit 1
    fi
    
    local utxo1_txid=$(echo "$utxo1" | cut -d: -f1)
    local utxo1_vout=$(echo "$utxo1" | cut -d: -f2)
    local utxo2_txid=$(echo "$utxo2" | cut -d: -f1)
    local utxo2_vout=$(echo "$utxo2" | cut -d: -f2)
    
    echo -e "${GREEN}✓ UTXO 1: ${utxo1_txid}:${utxo1_vout}${NC}"
    echo -e "${GREEN}✓ UTXO 2: ${utxo2_txid}:${utxo2_vout}${NC}"
    
    # Crear transacción con RBF (sequence < 0xfffffffe)
    print_separator
    echo -e "${CYAN}Paso 9: Crear transacción parent con RBF habilitado${NC}"
    echo -e "${YELLOW}Se espera: Transacción con 70 BTC para Trader, 29.99999 BTC cambio (fee 0.00001)${NC}"
    
    local inputs="[{\"txid\":\"${utxo1_txid}\",\"vout\":${utxo1_vout},\"sequence\":4294967293},{\"txid\":\"${utxo2_txid}\",\"vout\":${utxo2_vout},\"sequence\":4294967293}]"
    local outputs="{\"${TRADER_ADDRESS}\":70,\"${MINER_ADDRESS}\":29.99999}"
    
    echo -e "${YELLOW}Configurando sequence número para RBF (4294967293)...${NC}"
    local raw_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createrawtransaction "$inputs" "$outputs") || { echo -e "${RED}Error: No se pudo crear transacción raw${NC}"; exit 1; }
    echo -e "${GREEN}✓ Transacción raw creada con RBF habilitado${NC}"
    
    # Firmar transacción
    print_separator
    echo -e "${CYAN}Paso 10: Firmar transacción parent${NC}"
    echo -e "${YELLOW}Se espera: Firma criptográfica válida usando claves privadas de Miner${NC}"
    
    local signed_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} signrawtransactionwithwallet "$raw_tx" | jq -r '.hex') || { echo -e "${RED}Error: No se pudo firmar transacción${NC}"; exit 1; }
    echo -e "${GREEN}✓ Transacción firmada exitosamente${NC}"
    
    # Transmitir al mempool
    print_separator
    echo -e "${CYAN}Paso 11: Transmitir transacción parent al mempool${NC}"
    echo -e "${YELLOW}Se espera: Transacción en mempool, NO minada aún${NC}"
    
    PARENT_TXID=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest sendrawtransaction "$signed_tx") || { echo -e "${RED}Error: No se pudo transmitir transacción${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Parent TXID: ${PARENT_TXID}${NC}"
    
    # Verificar que está en mempool
    local mempool_check=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawmempool | grep -c "$PARENT_TXID")
    if [ "$mempool_check" -eq 0 ]; then
        echo -e "${RED}Error: Transacción no encontrada en mempool${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Transacción confirmada en mempool${NC}"
    
    # Guardar inputs para uso posterior
    PARENT_INPUTS="$inputs"
}

# Función para análisis técnico y JSON
analyze_transaction() {
    print_separator
    echo -e "${CYAN}Paso 12: Analizar transacción parent en mempool${NC}"
    echo -e "${YELLOW}Se espera: Detalles completos de la transacción usando getmempoolentry${NC}"
    
    # Obtener detalles del mempool
    local mempool_entry=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getmempoolentry "$PARENT_TXID") || { echo -e "${RED}Error: No se pudieron obtener detalles del mempool${NC}"; exit 1; }
    
    local raw_tx_details=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawtransaction "$PARENT_TXID" true) || { echo -e "${RED}Error: No se pudieron obtener detalles de transacción raw${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Detalles de transacción obtenidos${NC}"
    
    # Extraer información con jq
    print_separator
    echo -e "${CYAN}Paso 13: Extraer información detallada con jq${NC}"
    echo -e "${YELLOW}Se espera: Extracción de inputs, outputs, fees y weight${NC}"
    
    local input1_txid=$(echo "$raw_tx_details" | jq -r '.vin[0].txid')
    local input1_vout=$(echo "$raw_tx_details" | jq -r '.vin[0].vout')
    local input2_txid=$(echo "$raw_tx_details" | jq -r '.vin[1].txid')
    local input2_vout=$(echo "$raw_tx_details" | jq -r '.vin[1].vout')
    
    local output1_script=$(echo "$raw_tx_details" | jq -r '.vout[0].scriptPubKey.hex')
    local output1_amount=$(echo "$raw_tx_details" | jq -r '.vout[0].value')
    local output2_script=$(echo "$raw_tx_details" | jq -r '.vout[1].scriptPubKey.hex')
    local output2_amount=$(echo "$raw_tx_details" | jq -r '.vout[1].value')
    
    local fees_btc=$(echo "$mempool_entry" | jq -r '.fees.base')
    local fees_satoshis=$(echo "$fees_btc * 100000000" | bc | cut -d. -f1)
    local weight=$(echo "$mempool_entry" | jq -r '.weight')
    
    echo -e "${GREEN}✓ Información extraída:${NC}"
    echo -e "  • Fees: ${fees_satoshis} satoshis"
    echo -e "  • Weight: ${weight} vbytes"
    
    # Construir JSON técnico
    print_separator
    echo -e "${CYAN}Paso 14: Construir JSON estructurado${NC}"
    echo -e "${YELLOW}Se espera: JSON formateado con estructura específica del ejercicio${NC}"
    
    local technical_json=$(jq -n --arg input1_txid "$input1_txid" \
                                 --arg input1_vout "$input1_vout" \
                                 --arg input2_txid "$input2_txid" \
                                 --arg input2_vout "$input2_vout" \
                                 --arg output1_script "$output1_script" \
                                 --arg output1_amount "$output1_amount" \
                                 --arg output2_script "$output2_script" \
                                 --arg output2_amount "$output2_amount" \
                                 --arg fees "$fees_satoshis" \
                                 --arg weight "$weight" \
                                 '{
                                   "input": [
                                     {"txid": $input1_txid, "vout": $input1_vout},
                                     {"txid": $input2_txid, "vout": $input2_vout}
                                   ],
                                   "output": [
                                     {"script_pubkey": $output1_script, "amount": $output1_amount},
                                     {"script_pubkey": $output2_script, "amount": $output2_amount}
                                   ],
                                   "Fees": $fees,
                                   "Weight": $weight
                                 }')
    
    echo -e "${GREEN}✓ JSON de transacción parent:${NC}"
    echo "$technical_json" | jq .
}

# Función para demostrar CPFP
demonstrate_cpfp() {
    print_separator
    echo -e "${CYAN}Paso 15: Crear transacción child para CPFP${NC}"
    echo -e "${YELLOW}Se espera: Child que gasta output de cambio de parent (29.99999 BTC)${NC}"
    
    # Obtener detalles de parent para identificar output de cambio
    local raw_tx_details=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawtransaction "$PARENT_TXID" true)
    
    # Encontrar output de cambio (29.99999 BTC)
    local change_vout=""
    local change_amount=""
    
    echo -e "${YELLOW}Identificando output de cambio en transacción parent...${NC}"
    for i in 0 1; do
        local amount=$(echo "$raw_tx_details" | jq -r ".vout[$i].value")
        if [ "$amount" = "29.99999000" ]; then
            change_vout=$i
            change_amount=$amount
            break
        fi
    done
    
    if [ -z "$change_vout" ]; then
        echo -e "${RED}Error: No se pudo identificar output de cambio${NC}"
        echo -e "${YELLOW}Outputs disponibles:${NC}"
        echo "$raw_tx_details" | jq '.vout[] | {vout: .n, value: .value}'
        exit 1
    fi
    
    echo -e "${GREEN}✓ Output de cambio: vout ${change_vout}, cantidad: ${change_amount} BTC${NC}"
    
    # Crear child transaction
    print_separator
    echo -e "${CYAN}Paso 16: Construir y transmitir child transaction${NC}"
    echo -e "${YELLOW}Se espera: Transacción child que acelera parent mediante CPFP${NC}"
    
    local child_address=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getnewaddress "CPFP_Child") || { echo -e "${RED}Error: No se pudo generar dirección para child${NC}"; exit 1; }
    
    # Crear child transaction (29.99999 - 0.00001 fee = 29.99998)
    local child_inputs="[{\"txid\":\"${PARENT_TXID}\",\"vout\":${change_vout}}]"
    local child_outputs="{\"${child_address}\":29.99998}"
    
    local child_raw=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createrawtransaction "$child_inputs" "$child_outputs") || { echo -e "${RED}Error: No se pudo crear child transaction${NC}"; exit 1; }
    
    local child_signed=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} signrawtransactionwithwallet "$child_raw" | jq -r '.hex') || { echo -e "${RED}Error: No se pudo firmar child transaction${NC}"; exit 1; }
    
    CHILD_TXID=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest sendrawtransaction "$child_signed") || { echo -e "${RED}Error: No se pudo transmitir child transaction${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Child TXID: ${CHILD_TXID}${NC}"
    
    # Mostrar detalles de child en mempool
    print_separator
    echo -e "${CYAN}Paso 17: Analizar child transaction en mempool${NC}"
    echo -e "${YELLOW}Se espera: Detalles completos de child usando getmempoolentry${NC}"
    
    local child_mempool=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getmempoolentry "$CHILD_TXID") || { echo -e "${RED}Error: No se pudieron obtener detalles de child en mempool${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Child transaction en mempool:${NC}"
    echo "$child_mempool" | jq '{vsize, fees, depends}'
}

# Función para ejecutar RBF
execute_rbf() {
    print_separator
    echo -e "${CYAN}Paso 18: Crear replacement parent con fee incrementado${NC}"
    echo -e "${YELLOW}Se espera: Nueva versión de parent con fee aumentado en 10,000 satoshis${NC}"
    
    # Crear replacement con fee incrementado
    echo -e "${YELLOW}Configurando replacement transaction...${NC}"
    echo -e "${YELLOW}Fee original: 1,000 satoshis (0.00001 BTC)${NC}"
    echo -e "${YELLOW}Fee nuevo: 10,000 satoshis (0.0001 BTC)${NC}"
    
    # Nueva transacción con fee incrementado (29.99999 - 0.0001 = 29.9999 para cambio)
    local replacement_outputs="{\"${TRADER_ADDRESS}\":70,\"${MINER_ADDRESS}\":29.9999}"
    
    local replacement_raw=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest createrawtransaction "$PARENT_INPUTS" "$replacement_outputs") || { echo -e "${RED}Error: No se pudo crear replacement transaction${NC}"; exit 1; }
    
    local replacement_signed=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} signrawtransactionwithwallet "$replacement_raw" | jq -r '.hex') || { echo -e "${RED}Error: No se pudo firmar replacement transaction${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Replacement transaction creada y firmada${NC}"
    
    # Transmitir replacement transaction
    print_separator
    echo -e "${CYAN}Paso 19: Transmitir replacement transaction (RBF)${NC}"
    echo -e "${YELLOW}Se espera: Parent original reemplazada, child invalidada${NC}"
    
    REPLACEMENT_TXID=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest sendrawtransaction "$replacement_signed") || { echo -e "${RED}Error: No se pudo transmitir replacement transaction${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Replacement TXID: ${REPLACEMENT_TXID}${NC}"
    
    # Verificar que parent original fue reemplazada
    print_separator
    echo -e "${CYAN}Verificación: Parent original reemplazada${NC}"
    local original_in_mempool=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawmempool | grep -c "$PARENT_TXID" || true)
    local replacement_in_mempool=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawmempool | grep -c "$REPLACEMENT_TXID")
    
    if [ "$original_in_mempool" -eq 0 ] && [ "$replacement_in_mempool" -eq 1 ]; then
        echo -e "${GREEN}✓ Parent original reemplazada exitosamente${NC}"
        echo -e "${GREEN}✓ Replacement transaction en mempool${NC}"
    else
        echo -e "${RED}Error en proceso de reemplazo${NC}"
        exit 1
    fi
}

# Función para verificar conflicto
verify_conflict() {
    print_separator
    echo -e "${CYAN}Paso 20: Verificar estado de child transaction después de RBF${NC}"
    echo -e "${YELLOW}Se espera: Child transaction no debe existir en mempool${NC}"
    
    # Verificar que child ya no está en mempool
    local child_in_mempool=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawmempool | grep -c "$CHILD_TXID" || true)
    
    if [ "$child_in_mempool" -eq 0 ]; then
        echo -e "${GREEN}✓ Child transaction removida del mempool (esperado)${NC}"
        
        # Intentar getmempoolentry y mostrar error
        echo -e "${CYAN}Intentando getmempoolentry para child transaction...${NC}"
        local child_error=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getmempoolentry "$CHILD_TXID" 2>&1 || true)
        echo -e "${RED}Error esperado: ${child_error}${NC}"
    else
        echo -e "${RED}Inesperado: Child transaction aún en mempool${NC}"
        exit 1
    fi
    
    # Mostrar explicación técnica
    print_separator
    echo -e "${CYAN}Paso 21: Explicación técnica del conflicto RBF vs CPFP${NC}"
    echo -e "${YELLOW}Análisis detallado:${NC}"
    
    echo -e "${CYAN}ANTES del RBF:${NC}"
    echo -e "  • Parent transaction: ${PARENT_TXID}"
    echo -e "  • Child transaction: ${CHILD_TXID}"
    echo -e "  • Child gastaba vout de parent"
    echo -e "  • Ambas transacciones en mempool"
    
    echo -e "${CYAN}DESPUÉS del RBF:${NC}"
    echo -e "  • Parent original: REMOVIDA del mempool"
    echo -e "  • Replacement parent: ${REPLACEMENT_TXID}"
    echo -e "  • Child transaction: INVALIDADA automáticamente"
    
    echo -e "${CYAN}RAZÓN DEL CONFLICTO:${NC}"
    echo -e "${YELLOW}1. RBF reemplaza completamente la transacción parent${NC}"
    echo -e "${YELLOW}2. El nuevo parent tiene un TXID diferente${NC}"
    echo -e "${YELLOW}3. Child transaction referencia un UTXO que ya no existe${NC}"
    echo -e "${YELLOW}4. Bitcoin Core remueve automáticamente transacciones huérfanas${NC}"
    echo -e "${YELLOW}5. RBF y CPFP son técnicas mutuamente excluyentes${NC}"
}

# Función para confirmar transacción replacement
confirm_replacement_transaction() {
    print_separator
    echo -e "${CYAN}Paso 22: Minar bloque para confirmar replacement transaction${NC}"
    echo -e "${YELLOW}Se espera: Confirmar replacement transaction y actualizar saldos${NC}"
    
    # Minar un bloque para confirmar la replacement transaction
    local block_hash=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} generatetoaddress 1 "${MINER_ADDRESS}") || { echo -e "${RED}Error: No se pudo minar bloque de confirmación${NC}"; exit 1; }
    
    echo -e "${GREEN}✓ Bloque minado para confirmar replacement transaction${NC}"
    
    # Verificar que la replacement transaction está confirmada
    local confirmed_tx=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawtransaction "$REPLACEMENT_TXID" true)
    local confirmations=$(echo "$confirmed_tx" | jq -r '.confirmations')
    
    if [ "$confirmations" -gt 0 ]; then
        echo -e "${GREEN}✓ Replacement transaction confirmada con ${confirmations} confirmación(es)${NC}"
    else
        echo -e "${RED}⚠ Replacement transaction aún no confirmada${NC}"
    fi
}

# Función para mostrar resumen final
show_final_summary() {
    print_separator
    echo -e "${CYAN}Paso 23: Estado final del mempool${NC}"
    echo -e "${YELLOW}Se espera: Mempool vacío (transacciones confirmadas)${NC}"
    
    local final_mempool=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getrawmempool)
    echo -e "${GREEN}✓ Transacciones actuales en mempool:${NC}"
    echo "$final_mempool" | jq .
    
    local mempool_count=$(echo "$final_mempool" | jq '. | length')
    echo -e "${GREEN}Total de transacciones en mempool: ${mempool_count}${NC}"
    
    print_separator
    echo -e "${CYAN}Paso 25: Resumen de lo aprendido${NC}"
    
    echo -e "${CYAN}=== RESUMEN DEL EJERCICIO SEMANA 2 ===${NC}"
    echo -e "${GREEN}✓ Replace-By-Fee (RBF):${NC}"
    echo -e "    • Flujos de trabajo de billeteras Bitcoin con bitcoin-cli"
    echo -e "    • Mecanismo RBF permite reemplazar transacciones no confirmadas"
    echo -e "    • Fee incrementado en 10,000 satoshis según ejercicio"
    echo -e "    • RBF requiere señalización en sequence number"
    
    echo -e "${GREEN}✓ Child-Pays-for-Parent (CPFP):${NC}"
    echo -e "    • Permite acelerar transacciones parent con fees bajos"
    echo -e "    • Child transaction paga fee alto por ambas transacciones"
    echo -e "    • Miners procesan ambas juntas para maximizar ganancias"
    
    echo -e "${GREEN}✓ Impacto en Transacciones Child:${NC}"
    echo -e "    • Child transaction gastaba output de cambio de Parent"
    echo -e "    • RBF invalida automáticamente transacciones child dependientes"
    echo -e "    • Bitcoin Core remueve transacciones huérfanas del mempool"
    echo -e "    • Demostrado mediante comparación de mempool antes/después"
    
    echo -e "${RED}⚠ CONFLICTO RBF vs CPFP:${NC}"
    echo -e "    • Son técnicas mutuamente excluyentes"
    echo -e "    • RBF invalida cualquier child transaction existente"
    echo -e "    • Una vez que se hace RBF, CPFP ya no es posible"
    echo -e "    • Importante considerar cuál estrategia usar según el caso"
    
    echo -e "${CYAN}=== TRANSACCIONES GENERADAS ===${NC}"
    echo -e "Parent original (removida): ${PARENT_TXID}"
    echo -e "Child transaction (invalidada): ${CHILD_TXID}"
    echo -e "Replacement parent (activa): ${REPLACEMENT_TXID}"
    
    print_separator
    echo -e "${CYAN}Paso 24: Verificar saldos finales de billeteras${NC}"
    echo -e "${YELLOW}Se espera: Saldos actualizados tras confirmación de replacement transaction${NC}"
    
    local final_miner_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${MINER_WALLET} getbalance)
    local final_trader_balance=$(${BITCOIN_BIN_DIR}/bitcoin-cli -regtest -rpcwallet=${TRADER_WALLET} getbalance)
    
    print_separator
    echo -e "${CYAN}=== SALDOS FINALES DE BILLETERAS ===${NC}"
    echo -e "${GREEN}Saldo final Miner: ${final_miner_balance} BTC${NC}"
    echo -e "${GREEN}Saldo final Trader: ${final_trader_balance} BTC${NC}"
    
    # Explicar las matemáticas
    print_separator
    echo -e "${CYAN}=== ANÁLISIS DE TRANSFERENCIAS ===${NC}"
    echo -e "${YELLOW}Matemáticas de la demostración:${NC}"
    echo -e "  • Miner inicial: 150 BTC (después de minado)"
    echo -e "  • Miner gastó: 100 BTC (2 UTXOs de 50 BTC cada uno)"
    echo -e "  • Trader recibió: 70 BTC (mediante replacement transaction)"
    echo -e "  • Miner recibió cambio: 29.9999 BTC (100 - 70 - 0.0001 fee)"
    echo -e "  • Miner minó 1 bloque adicional: +50 BTC (confirmación)"
    echo -e "  • ${CYAN}Saldo esperado Miner: 150 - 100 + 29.9999 + 50 = 129.9999 BTC${NC}"
    echo -e "  • ${CYAN}Saldo esperado Trader: 0 + 70 = 70 BTC${NC}"
    
    # Verificar si los saldos coinciden con lo esperado
    local expected_miner=$(echo "129.9999" | bc)
    local expected_trader="70.00000000"
    
    echo ""
    if [ "$(echo "$final_trader_balance == 70" | bc)" -eq 1 ]; then
        echo -e "${GREEN}✓ Saldo Trader correcto: ${final_trader_balance} BTC${NC}"
    else
        echo -e "${RED}⚠ Saldo Trader inesperado: ${final_trader_balance} BTC (esperado: 70)${NC}"
    fi
    
    if [ "$(echo "$final_miner_balance >= 129.99" | bc)" -eq 1 ] && [ "$(echo "$final_miner_balance <= 130.01" | bc)" -eq 1 ]; then
        echo -e "${GREEN}✓ Saldo Miner correcto: ${final_miner_balance} BTC${NC}"
    else
        echo -e "${RED}⚠ Saldo Miner inesperado: ${final_miner_balance} BTC (esperado: ~129.9999)${NC}"
    fi
    
    print_separator
    echo -e "${GREEN}✓ Demostración RBF vs CPFP completada exitosamente${NC}"
}

# Función principal del módulo
demonstrate_rbf_vs_cpfp() {
    create_rbf_parent
    analyze_transaction
    demonstrate_cpfp
    execute_rbf
    verify_conflict
    confirm_replacement_transaction
    show_final_summary
}