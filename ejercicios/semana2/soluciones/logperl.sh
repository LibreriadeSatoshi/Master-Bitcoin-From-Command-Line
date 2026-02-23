#!/bin/bash

set -euo pipefail

# --- VARIABLES DE CONFIGURACIÓN ---
BITCOIN_VERSION="29.0"
BITCOIN_USER="bitcoin"
BITCOIN_DATA_DIR="/home/bitcoin"
BITCOIN_CONF_DIR="${BITCOIN_DATA_DIR}/.bitcoin"
BITCOIN_CONF_FILE="${BITCOIN_CONF_DIR}/bitcoin.conf"

# --- ALIAS COMANDO ---
bcli() {
    bitcoin-cli -datadir="${BITCOIN_CONF_DIR}" -regtest "$@"
}

# --- ESTILOS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- LOGGING ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC}   $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

#### PRE: Para empezar de 0, el script primero parará y borrará cualquier rastro de blockchain
reinicio_de_0() {
    log "Gestionando proceso bitcoind..."
    
    # 1. PARADA LIMPIA
    if pgrep -x "bitcoind" > /dev/null; then
        warn "Deteniendo nodo existente..."
        # Usamos bcli para parar (más limpio)
        bitcoin-cli stop
        sleep 2
    fi

    # 2. BORRADO DE DATOS (FRESH START)
    if [ -d "${BITCOIN_CONF_DIR}/regtest" ]; then
        log "Borrando blockchain antigua (Regtest Reset)..."
        rm -rf "${BITCOIN_CONF_DIR}/regtest"
    fi

    # 3. ARRANQUE
    log "Iniciando nodo limpio..."
    # Aquí no usamos bcli porque es el demonio, no el cliente
    bitcoind -daemon > /dev/null
    sleep 2
}

# Crear dos billeteras llamadas Miner y Trader.
crear_wallets() {
    log "Fase 1: Creando Wallets..."
    
    # Como hemos borrado 'regtest', sabemos que NO existen wallets.
    # Podemos crearlas directamente sin comprobaciones complejas.
    crear_simple() {
        local WNAME=$1
        if ! bcli -named createwallet wallet_name="$WNAME" >/dev/null 2>&1; then
            error "Fallo al crear wallet '$WNAME'."
        fi
        ok "Wallet '$WNAME' creada."
    }

    crear_simple "Miner"
    crear_simple "Trader"
}

# Fondear la billetera Miner con al menos el equivalente a 3 recompensas en bloque en satoshis (Saldo inicial: 150 BTC).
fondeando_cartera_miner() {
  log "Fase 2: Fondeando cartera 'Miner'..."

  # Bucle que se ejecuta mientras el balance sea menor a 151
  while [ $(echo "$(bitcoin-cli -rpcwallet=Miner getbalances | jq -r '.mine.trusted') < 150" | bc -l) -eq 1 ]; do
      local MINER_ADDR=$(bcli -rpcwallet=Miner getnewaddress "Recompensa")
      bcli generatetoaddress 1 "$MINER_ADDR" >/dev/null 2>&1
  done
  ok "Saldo de 'Miner': $(bitcoin-cli -rpcwallet=Miner getbalances | jq -r '.mine.trusted')"
}

# Crear una transacción desde Miner a Trader con la siguiente estructura (llamémosla la transacción parent):
#   Entrada[0]: Recompensa en bloque de 50 BTC.
#   Entrada[1]: Recompensa en bloque de 50 BTC.
#   Salida[0]: 70 BTC para Trader.
#   Salida[1]: 29.99999 BTC de cambio para Miner.
#   Activar RBF (Habilitar RBF para la transacción).
# Firmar y transmitir la transacción parent, pero no la confirmes aún.
prepara_tx_de_miner_a_trader01() {
  log "Fase 3: Preparando transacción 'parent' de 'Miner' a 'Trader'..."

  # Usaré una direccion "taproot" (bech32m, segwit v1) para este ejemplo "bcrt1p..." 
  # donde la "p" determina que es taproot, si fuera "q" sería segwit v0
  local TRADER_ADDR=$(bcli -rpcwallet=Trader -named getnewaddress address_type=bech32m)
  local MINER_CHANGE_ADDR=$(bcli -rpcwallet=Miner -named getnewaddress address_type=bech32m)
  # Los montos vienen fijados por el enunciado
  local AMOUNT_TRADER=70
  local AMOUNT_CHANGE=29.99999

  # 2. Selección inteligente de UTXOs con jq
  # Suma UTXOs hasta tener al menos AMOUNT_TRADER=70 BTC y formatea la salida para el CLI.
  INPUTS=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -c --argjson target "${AMOUNT_TRADER}" '
    reduce .[] as $item (
      {sum: 0, txs: []}; 
      if .sum < $target then 
        {sum: (.sum + $item.amount), txs: (.txs + [{txid: $item.txid, vout: $item.vout}])} 
      else 
        . 
      end
    ) | .txs
  ')
  ok "Escogidos los UTXOS para gastar: $(echo ${INPUTS} | jq -r '[.[].txid] | join(", ")')"

  # 3. Crear Transacción Cruda (Fijando los 2 outputs exactos)
  RAW_TX=$(bcli -named createrawtransaction \
    inputs="$INPUTS" \
    outputs='{"'$TRADER_ADDR'": '$AMOUNT_TRADER', "'$MINER_CHANGE_ADDR'": '$AMOUNT_CHANGE'}' \
    replaceable=true)
  ok "Creada la Raw Transaction con los montos fijos $AMOUNT_TRADER para Trader y $MINER_CHANGE_ADDR de cambio y RBF activado."

  # 4. Firmar
  SIGNED_HEX=$(bcli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring="$RAW_TX" | jq -r '.hex')
  ok "Transacción firmada."

  # 5. Enviar a Mempool
  TXID_PARENT_01=$(bcli -rpcwallet=Miner -named sendrawtransaction hexstring="$SIGNED_HEX")
  ok "Transacción subida a la Mempool."
}


# Imprime el JSON anterior en la terminal.
formatear_json() {
  log "Fase 4: Formateando JSON..."

  # 1. Hemos guardado la transaccion que usaremos en la variable TXID_PARENT_01
  # 2. Obtenemos los detalles de la transacción (raw transaction) de la "MEMPOOL"
  # El parámetro 'verbose=true' es necesario para obtener el JSON completo
  TX_DATA=$(bitcoin-cli -named getrawtransaction txid="${TXID_PARENT_01}" verbose=true)

  # 3. Obtenemos los datos de la mempool (fees y weight real)
  # Nota: La transacción debe estar en la mempool para que este comando funcione
  MEMPOOL_DATA=$(bitcoin-cli -named getmempoolentry txid="${TXID_PARENT_01}")

  # 4. Extraemos y formateamos los campos con JQ
  # Extraemos inputs (txid y vout)
  INPUTS=$(echo "$TX_DATA" | jq -c '[.vin[] | {txid: .txid, vout: .vout}]')
  # Extraemos outputs (script_pubkey y amount)
  OUTPUTS=$(echo "$TX_DATA" | jq -c '[.vout[] | {script_pubkey: .scriptPubKey.hex, amount: .value}]')

  # Extraemos Fees (desde la mempool) y Weight
  FEES=$(echo "$MEMPOOL_DATA" | jq -r '.fees.base')
  VSIZE=$(echo "$TX_DATA" | jq -r '.vsize')

  # 5. CONSTRUCCIÓN DEL JSON FINAL
  # Usamos jq -n para montar la estructura exacta que te han pedido
  FINAL_JSON=$(jq -n \
    --argjson ins "$INPUTS" \
    --argjson outs "$OUTPUTS" \
    --arg fees "$FEES" \
    --arg weight "$VSIZE" \
    '{
      input: $ins,
      output: $outs,
      Fees: $fees,
      Weight: $weight
    }')

  # 6. Resultado por stdout
  ok "$FINAL_JSON"
}

# Crea una nueva transmisión que gaste la transacción anterior (parent). Llamémosla transacción child.
#   Entrada[0]: Salida de Miner de la transacción parent.
#   Salida[0]: Nueva dirección de Miner. 29.99998 BTC.
prepara_tx_de_miner_a_miner01() {
  log "Fase 5: Preparando transacción 'child' de 'Miner' a 'Miner'..."

  # Obtenemos el VOUT directamente de la transacción padre.
  # Buscamos el output (.vout[]) cuyo valor sea exactamente 29.99999 y extraemos su índice (.n)
  local VOUT_CHILD=$(bcli -named getrawtransaction txid="${TXID_PARENT_01}" verbose=true | jq -r '.vout[] | select(.value == 29.99999) | .n')

  # Validación de seguridad
  if [ -z "$VOUT_CHILD" ]; then
      error "No se encontró el UTXO de 29.99999 en la tx ${TXID_PARENT_01}"
  fi
  ok "Encontrado el UTXO a gastar: TXID=${TXID_PARENT_01}, VOUT=${VOUT_CHILD}"

  # 2. Generamos la nueva dirección de destino para el Miner
  local MINER_NEW_ADDR=$(bcli -rpcwallet=Miner -named getnewaddress address_type=bech32m)
  local AMOUNT_CHILD=29.99998

  # 3. Creamos la Raw Transaction (La transacción Child)
  local RAW_TX_CHILD=$(bcli -named createrawtransaction \
    inputs='[{"txid":"'${TXID_PARENT_01}'","vout":'${VOUT_CHILD}'}]' \
    outputs='{"'${MINER_NEW_ADDR}'": '${AMOUNT_CHILD}'}')
  
  ok "Creada la Raw Transaction Child."

  # 4. Firmamos la transacción con la cartera del Miner
  local SIGNED_HEX_CHILD=$(bcli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring="${RAW_TX_CHILD}" | jq -r '.hex')
  ok "Transacción Child firmada."

  # 5. La enviamos a la Mempool (¡Gastando un UTXO sin confirmar!)
  # Usamos una variable global por si la necesitas en el siguiente paso del ejercicio
  TXID_CHILD_01=$(bcli -rpcwallet=Miner -named sendrawtransaction hexstring="${SIGNED_HEX_CHILD}")
  ok "Transacción Child subida a la Mempool. TXID: ${TXID_CHILD_01}"
}

# Realiza una consulta getmempoolentry para la transacción child y muestra la salida.
consulta_mempool_child_antes_rbf() {
  log "Fase 6: Consultando getmempoolentry para la transacción 'child'..."

  # Verificamos que la variable exista para no ejecutar el comando en vacío
  if [ -z "${TXID_CHILD_01:-}" ]; then
      error "No se encontró el TXID de la transacción child. ¿Se ejecutó la fase anterior?"
  fi

  # Ejecutamos la consulta a la mempool
  local MEMPOOL_CHILD_salida=$(bcli -named getmempoolentry txid="${TXID_CHILD_01}")

  ok "Resultado de getmempoolentry para Child TX (${TXID_CHILD_01}):"
  
  # Imprimimos la salida directamente formateada con jq para que sea legible en la terminal
  echo "$MEMPOOL_CHILD_salida" | jq .
}

# Ahora, aumenta la tarifa de la transacción parent utilizando RBF. No uses bitcoin-cli bumpfee, en su lugar, crea manualmente una transacción conflictiva que tenga las mismas entradas que la transacción parent pero salidas diferentes, ajustando sus valores para aumentar la tarifa de la transacción parent en 10,000 satoshis.
# Firma y transmite la nueva transacción principal.
rbf_manual_parent() {
  log "Fase 7: Ejecutando RBF manual sobre la transacción Parent..."

  # 1. Recuperamos los datos de la transacción padre original.
  local TX_DATA_PARENT=$(bcli -named getrawtransaction txid="${TXID_PARENT_01}" verbose=true)
  local INPUTS_CONFLICTO=$(echo "$TX_DATA_PARENT" | jq -c '[.vin[] | {txid: .txid, vout: .vout}]')

  # 2. Extraemos las direcciones destino directamente de la transacción original
  # Sabemos que vout[0] es el Trader y vout[1] es el cambio del Miner
  local TRADER_ADDR=$(echo "$TX_DATA_PARENT" | jq -r '.vout[0].scriptPubKey.address')
  local MINER_CHANGE_ADDR=$(echo "$TX_DATA_PARENT" | jq -r '.vout[1].scriptPubKey.address')

  # 3. Ajustamos las matemáticas para subir el fee en 10,000 sats (0.0001 BTC).
  local AMOUNT_TRADER=70
  local AMOUNT_CHANGE_NUEVO=29.99989

  # 4. Creamos la Transacción Conflictiva (Mismos inputs, diferentes outputs)
  local RAW_TX_RBF=$(bcli -named createrawtransaction \
    inputs="$INPUTS_CONFLICTO" \
    outputs='{"'$TRADER_ADDR'": '$AMOUNT_TRADER', "'$MINER_CHANGE_ADDR'": '$AMOUNT_CHANGE_NUEVO'}')
  
  ok "Transacción conflictiva creada (Fee aumentado en 10k sats)."

  # 5. Firmamos la nueva transacción
  local SIGNED_RBF=$(bcli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring="$RAW_TX_RBF" | jq -r '.hex')

  # 6. La enviamos a la red. 
  TXID_PARENT_RBF=$(bcli -rpcwallet=Miner -named sendrawtransaction hexstring="$SIGNED_RBF")
  ok "RBF ejecutado con éxito. NUEVO TXID Parent: ${TXID_PARENT_RBF}"
}

# Realiza otra consulta getmempoolentry para la transacción child y muestra el resultado.
# Realiza otra consulta getmempoolentry para la transacción child y muestra el resultado.
consulta_mempool_child_despues_rbf() {
  log "Fase 8: Consultando getmempoolentry para la transacción 'child' DESPUÉS del RBF..."

  # Como el padre fue reemplazado, la transacción hija ha sido expulsada de la mempool.
  # El comando getmempoolentry va a fallar. Usamos '|| true' para que set -e no aborte el script,
  # y '2>&1' para capturar el mensaje de error que escupe el nodo y poder mostrarlo.
  local MEMPOOL_CHILD_salida
  MEMPOOL_CHILD_salida=$(bcli -named getmempoolentry txid="${TXID_CHILD_01}" 2>&1 || true)

  warn "Resultado de getmempoolentry para Child TX (${TXID_CHILD_01}):"
  
  # Imprimimos la salida en bruto porque ya no será un JSON válido, sino un texto de error.
  echo "$MEMPOOL_CHILD_salida"
}

# Imprime una explicación en la terminal de lo que cambió en los dos resultados 
# de getmempoolentry para las transacciones child y por qué.
explicacion_final() {
  log "Fase 9: Imprimiendo explicación técnica de los eventos en la Mempool..."
  
  echo -e ""
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${YELLOW}          EXPLICACIÓN DEL GURÚ: EL EFECTO DEL RBF EN LA MEMPOOL       ${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "1. ${GREEN}ANTES DEL RBF:${NC}"
  echo -e "   La consulta 'getmempoolentry' de la transacción Child devolvió un"
  echo -e "   JSON válido con todos sus datos. Esto ocurrió porque la Child"
  echo -e "   estaba gastando legítimamente un UTXO (el cambio de 29.99999 BTC)"
  echo -e "   de la transacción Parent original, la cual estaba en la mempool."
  echo -e ""
  echo -e "2. ${RED}DESPUÉS DEL RBF:${NC}"
  echo -e "   La consulta falló devolviendo 'Transaction not in mempool'. Al"
  echo -e "   ejecutar el RBF, creamos una transacción Parent conflictiva nueva"
  echo -e "   que gastaba los mismos billetes de 50 BTC pero pagando más fee."
  echo -e "   El nodo aceptó la nueva y eliminó la Parent original de su memoria."
  echo -e ""
  echo -e "3. ${BLUE}¿POR QUÉ DESAPARECIÓ LA CHILD? (Descendant Eviction):${NC}"
  echo -e "   Al borrarse la Parent original, el recibo (TXID) y el UTXO que la"
  echo -e "   transacción Child intentaba gastar dejaron de existir en la red."
  echo -e "   La Child se volvió matemáticamente inválida. El nodo Bitcoin aplica"
  echo -e "   una regla llamada 'Descendant Eviction' (Expulsión de Descendientes),"
  echo -e "   borrando automáticamente cualquier transacción que dependa de una"
  echo -e "   que acaba de ser reemplazada."
  echo -e "${CYAN}======================================================================${NC}"
  echo -e ""
  ok "Ejercicio completado."
}

reinicio_de_0
crear_wallets
fondeando_cartera_miner
prepara_tx_de_miner_a_trader01
formatear_json
sleep 1
prepara_tx_de_miner_a_miner01
consulta_mempool_child_antes_rbf
sleep 1
rbf_manual_parent
consulta_mempool_child_despues_rbf
explicacion_final
