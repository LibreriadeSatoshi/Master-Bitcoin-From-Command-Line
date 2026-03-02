#!/bin/bash

###### Enunciado del Problema
# Las transacciones multisig son un aspecto fundamental de la "criptografía Bitcoin compleja" que permite la copropiedad de UTXOs de Bitcoin. Juegan un papel crucial en las soluciones de custodia conjunta para los protocolos de la Capa 2 (L2).
# Los protocolos L2 comúnmente comienzan estableciendo una transacción de financiamiento multisig entre las partes involucradas. Por ejemplo, en Lightning, ambas partes pueden financiar conjuntamente la transacción antes de llevar a cabo sus transacciones relámpago. Al cerrar el canal, pueden liquidar el multisig para reclamar sus respectivas partes.

#En este ejercicio, nuestro objetivo es simular una transferencia básica de acciones multisig entre dos participantes, Alice y Bob.
###############

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
# Redirigimos todo a stderr (>&2) para separar la información visual de los datos puros.
log() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
ok()  { echo -e "${GREEN}[OK]${NC}   $1" >&2; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error(){ echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }

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

# 1. Crear tres monederos: `Miner`, `Alice` y `Bob`.
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
    crear_simple "Alice"
    crear_simple "Bob"
}

# 2.a. Fondear los monederos generando algunos bloques para `Miner`
fondeando_cartera_miner() {
  log "Fase 2.a: Fondeando cartera 'Miner'..."

  # Bucle que se ejecuta mientras el balance sea menor a 151
  while [ $(echo "$(bitcoin-cli -rpcwallet=Miner getbalances | jq -r '.mine.trusted') < 150" | bc -l) -eq 1 ]; do
      local MINER_ADDR=$(bcli -rpcwallet=Miner getnewaddress "Recompensa")
      bcli generatetoaddress 1 "$MINER_ADDR" >/dev/null 2>&1
  done
  ok "Saldo de 'Miner': $(bitcoin-cli -rpcwallet=Miner getbalances | jq -r '.mine.trusted')"
}

# 2.b. y enviando algunas monedas a `Alice` y `Bob`.
enviar_fondos() {
    local ORIGEN=$1
    local DESTINO=$2
    local MONTO=$3

    log "Preparando envío de $MONTO BTC de '$ORIGEN' a '$DESTINO'..."

    local ADDR_DESTINO
    ADDR_DESTINO=$(bcli -rpcwallet="$DESTINO" getnewaddress "Cobro_$ORIGEN")

    local TXID
    TXID=$(bcli -rpcwallet="$ORIGEN" sendtoaddress "$ADDR_DESTINO" "$MONTO") || return 1

    # Retornamos el TXID como salida de la función
    echo "$TXID"
}

# 3. Crear un wallet Multisig 2-de-2 combinando los descriptors de `Alice` y `Bob`. Uilizar la funcion "multi" wsh(multi(2,descAlice,descBob) para crear un "output descriptor". Importar el descriptor al Wallet Multisig. Generar una direccion.
crear_multisig_2_de_2() {
    local W1=$1
    local W2=$2
    local W_MULTI=$3

    log "Extrayendo claves PÚBLICAS (xpubs) de $W1 y $W2..."
    
    # Filtramos por '/0/*' para asegurarnos de usar la rama de recepción, no la de cambio.
    local CLAVE_1=$(bcli -rpcwallet="$W1" listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh")) | select(.desc | contains("/0/*")) | .desc' | cut -d'#' -f1 | sed 's/wpkh(//;s/)$//')
    local CLAVE_2=$(bcli -rpcwallet="$W2" listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh")) | select(.desc | contains("/0/*")) | .desc' | cut -d'#' -f1 | sed 's/wpkh(//;s/)$//')

    # 2. Crear wallet Multisig (Watch-Only)
    log "Creo la wallet multisig watch-only con 'createwallet disable_private_keys=true blank=true' ..."
    bcli -named createwallet wallet_name="$W_MULTI" disable_private_keys=true blank=true > /dev/null

    # 3. Construir descriptor multisig y obtener su Checksum
    log "Contruir el descriptor multisig y obtenemos su checksum"
    local RAW="wsh(multi(2,$CLAVE_1,$CLAVE_2))"
    local FULL_DESC=$(bcli getdescriptorinfo "$RAW" | jq -r '.descriptor')

    log "Importando descriptor Multisig con rango [0,100]..."

    # 4. Importar con el parámetro RANGE (Obligatorio para descriptores HD con /*)
    local IMPORT_RES
    IMPORT_RES=$(bcli -rpcwallet="$W_MULTI" importdescriptors "[{\"desc\": \"$FULL_DESC\", \"active\": true, \"internal\": false, \"timestamp\": \"now\", \"range\": [0, 100]}]")
    
    # Verificamos si la importación tuvo éxito
    if echo "$IMPORT_RES" | grep -q '"success": false'; then
        # Mandamos el error también por stderr
        error "Fallo al importar descriptor: $IMPORT_RES"
        return 1
    fi

    # 5. Generar y devolver la dirección
    bcli -rpcwallet="$W_MULTI" getnewaddress "Fondeo_Multisig"
}

# 4. Crear una Transacción Bitcoin Parcialmente Firmada (PSBT) para financiar la dirección multisig con 20 BTC, tomando 10 BTC de Alice y 10 BTC de Bob, y proporcionando el cambio correcto a cada uno de ellos.
crear_psbt_conjunta() {
    local W1=$1
    local W2=$2
    local ADDR_MULTI=$3

    log "$W1 creando su parte de la PSBT (Aportando 10 BTC + calculando cambio)..."
    local PSBT_W1
    PSBT_W1=$(bcli -rpcwallet="$W1" walletcreatefundedpsbt "[]" "[{\"$ADDR_MULTI\": 10}]" | jq -r '.psbt')
    
    if [ -z "$PSBT_W1" ] || [ "$PSBT_W1" == "null" ]; then
        error "Fallo al crear la PSBT base para $W1."
    fi

    log "$W2 creando su parte de la PSBT (Aportando 10 BTC + calculando cambio)..."
    local PSBT_W2
    PSBT_W2=$(bcli -rpcwallet="$W2" walletcreatefundedpsbt "[]" "[{\"$ADDR_MULTI\": 10}]" | jq -r '.psbt')
    
    if [ -z "$PSBT_W2" ] || [ "$PSBT_W2" == "null" ]; then
        error "Fallo al crear la PSBT base para $W2."
    fi

    log "Fusionando aportaciones en una única PSBT (JoinPSBTs)..."
    local PSBT_JOINED
    PSBT_JOINED=$(bcli joinpsbts "[\"$PSBT_W1\", \"$PSBT_W2\"]")
    
    if [ -z "$PSBT_JOINED" ] || [ "$PSBT_JOINED" == "null" ]; then
        error "Fallo al unir las PSBTs."
    fi

    # STDOUT: Devolvemos únicamente el string de la PSBT fusionada
    echo "$PSBT_JOINED"
}

firmar_y_transmitir_psbt() {
    local PSBT_BASE=$1
    local W1=$2
    local W2=$3

    log "$W1 firmando su parte de la PSBT..."
    local PSBT_FIRMADA_1
    PSBT_FIRMADA_1=$(bcli -rpcwallet="$W1" walletprocesspsbt "$PSBT_BASE" | jq -r '.psbt')

    log "$W2 firmando su parte de la PSBT..."
    local PSBT_FIRMADA_2
    PSBT_FIRMADA_2=$(bcli -rpcwallet="$W2" walletprocesspsbt "$PSBT_FIRMADA_1" | jq -r '.psbt')

    log "Finalizando la transacción (extrayendo HEX crudo)..."
    local TX_HEX
    TX_HEX=$(bcli finalizepsbt "$PSBT_FIRMADA_2" | jq -r '.hex')

    log "Transmitiendo la transacción a la red (Mempool)..."
    local TXID
    TXID=$(bcli sendrawtransaction "$TX_HEX") || return 1
    
    # STDOUT: Solo devolvemos el TXID
    echo "$TXID"
}

# 5. Confirmar el saldo mediante la minería de algunos bloques adicionales.
minar_y_confirmar() {
    local NUM_BLOQUES=$1
    
    local MINER_ADDR
    MINER_ADDR=$(bcli -rpcwallet=Miner getnewaddress "Confirmacion")
    bcli generatetoaddress "$NUM_BLOQUES" "$MINER_ADDR" > /dev/null
    
    # Preguntamos al nodo la altura de la blockchain
    local TOTAL_BLOQUES
    TOTAL_BLOQUES=$(bcli getblockcount)
    ok "Bloque(s) minado(s). La blockchain de Regtest tiene ahora $TOTAL_BLOQUES bloques en total."
}

# 6. Imprimir los saldos finales de `Alice` y `Bob`.
imprimir_saldo() {
    local WALLET=$1
    # Extraemos tanto el saldo trusted como el inmaduro por si acaso
    local SALDO
    SALDO=$(bcli -rpcwallet="$WALLET" getbalances | jq -r '.mine.trusted')
    ok "Saldo final de '$WALLET': $SALDO BTC"
}

# --- FASE 7: LIQUIDACIÓN DEL MULTISIG ---
# 1. Crear una PSBT para gastar fondos del wallet Multisig, enviando 3 BTC a Alice.
liquidar_multisig() {
    local W_MULTI=$1
    local W_ALICE=$2
    local W_BOB=$3

    log "Iniciando liquidación: El 'Contable' (Multisig) redacta el contrato..."

    # Generamos nuevas direcciones de cobro
    local ADDR_ALICE
    ADDR_ALICE=$(bcli -rpcwallet="$W_ALICE" getnewaddress "Cierre_Canal_Alice")
    
    local ADDR_BOB
    ADDR_BOB=$(bcli -rpcwallet="$W_BOB" getnewaddress "Cierre_Canal_Bob")

    # Crear PSBT: Enviamos 3 BTC a Alice. Usamos la opción 'changeAddress' para que 
    # TODO el resto (los ~17 BTC menos comisiones) vaya a Bob. Esto vacía el Multisig.
    local PSBT_LIQ
    PSBT_LIQ=$(bcli -rpcwallet="$W_MULTI" walletcreatefundedpsbt "[]" "[{\"$ADDR_ALICE\": 3}]" 0 "{\"changeAddress\": \"$ADDR_BOB\"}" | jq -r '.psbt')

    if [ -z "$PSBT_LIQ" ] || [ "$PSBT_LIQ" == "null" ]; then
        error "Fallo al crear la PSBT de liquidación."
        return 1
    fi

    # Devolvemos solo la PSBT al stdout
    echo "$PSBT_LIQ"
}


#### EJECUCION DEL PROGRAMA
reinicio_de_0
crear_wallets
fondeando_cartera_miner
# Capturamos el TXID directamente en una variable
TXID_ALICE=$(enviar_fondos "Miner" "Alice" 50)
ok "Transacción para Alice registrada: $TXID_ALICE"

TXID_BOB=$(enviar_fondos "Miner" "Bob" 30)
ok "Transacción para Bob registrada: $TXID_BOB"
    
# Minamos para asegurar ambos
log "Minar bloque para que las transacciones queden en la blockchain."
bcli generatetoaddress 1 $(bcli -rpcwallet=Miner getnewaddress) > /dev/null
ok "Minado bloque para regtest."

# VERIFICACIÓN DE TRANSACCIONES EN LA BLOCKCHAIN

# --- VERIFICACIÓN PARA ALICE ---
log "Verificando transacción con "gettransaction" $TXID_ALICE para Alice..."
# Comprobamos confirmaciones > 0. El flag -e en bash (set -e) hará que falle si bcli da error.
[[ $(bcli -rpcwallet=Alice gettransaction "$TXID_ALICE" | jq -r '.confirmations') -gt 0 ]] && ok "TX Alice confirmada, está en la cadena de bloques." || error "TX Alice no confirmada."

log "Verificando saldo con "getbalances" 'trusted' para Alice..." 
# El saldo 'trusted' es el único que Bitcoin Core permite gastar por defecto en una PSBT financiada.
[[ $(echo "$(bcli -rpcwallet=Alice getbalances | jq -r '.mine.trusted') >= 50" | bc -l) -eq 1 ]] && ok "Saldo Alice verificado (>= 50 BTC). Puede gastarlo." || error "Saldo Alice insuficiente o no trusted."

# --- VERIFICACIÓN PARA BOB ---
log "Verificando transacción con "gettransaction" $TXID_BOB para Bob..."
[[ $(bcli -rpcwallet=Bob gettransaction "$TXID_BOB" | jq -r '.confirmations') -gt 0 ]] && ok "TX Bob confirmada, está en la cadena de bloques." || error "TX Bob no confirmada."

log "Verificando saldo con "getbalances" 'trusted' para Bob..." 
# Bob recibió 30 BTC según tu script, comprobamos que estén disponibles.
[[ $(echo "$(bcli -rpcwallet=Bob getbalances | jq -r '.mine.trusted') >= 30" | bc -l) -eq 1 ]] && ok "Saldo Bob verificado (>= 30 BTC). Puede gastarlo." || error "Saldo Bob insuficiente o no trusted."

ok "Alice y Bob tienen sus UTXOs anclados y listos para la Fase 3."

log "Fase 3: Configurando la billetera compartida..."
DIRECCION_MULTISIG=$(crear_multisig_2_de_2 "Alice" "Bob" "Multisig")
ok "Billetera Multisig lista. Dirección de depósito: $DIRECCION_MULTISIG"

# --- FASE 4: CONSTRUCCIÓN DE LA PSBT CONJUNTA ---
log "Fase 4: Construyendo la PSBT conjunta para financiar el Multisig con 20 BTC..."

# Capturamos la salida de la función en la variable PSBT_FONDEO
PSBT_FONDEO=$(crear_psbt_conjunta "Alice" "Bob" "$DIRECCION_MULTISIG")
PSBT_DECODIFICADA=$(bcli decodepsbt "$PSBT_FONDEO" | jq .)

# Verificamos que la variable no esté vacía antes de celebrar
if [ -n "$PSBT_FONDEO" ]; then
    ok "PSBT base generada con éxito."
    
    # 1. FIRMAR Y TRANSMITIR (Fin real del Paso 4)
    TXID_FONDEO=$(firmar_y_transmitir_psbt "$PSBT_FONDEO" "Alice" "Bob")
    ok "Transacción de fondeo Multisig transmitida: $TXID_FONDEO"

    # 2. CONFIRMAR SALDOS (Paso 5)
    log "Fase 5: Minando 1 bloque para confirmar los movimientos..."
    minar_y_confirmar 1

    # 3. IMPRIMIR SALDOS FINALES (Paso 6)
    log "Fase 6: Imprimiendo saldos tras el fondeo del Multisig..."
    imprimir_saldo "Alice"
    imprimir_saldo "Bob"
    
    # Imprimimos el saldo del Multisig para verificar que recibió los 20 BTC
    imprimir_saldo "Multisig"

else
    error "La generación de la PSBT falló."
fi

# ==========================================
#      LIQUIDACIÓN DEL MULTISIG (CIERRE)
# ==========================================
echo
log "Fase Final: Liquidando el Multisig..."

# 1. El Multisig crea la PSBT
log "Prepara transacción: 3 BTC para Alice y el cambio se regresa a la Multisig ..."
PSBT_CIERRE=$(liquidar_multisig "Multisig" "Alice" "Multisig")
ok "Contrato de liquidación redactado."

# 2. Firmar la PSBT por Alice
log "Alice revisa y aplica su firma (1/2)..."
PSBT_CIERRE_ALICE=$(bcli -rpcwallet=Alice walletprocesspsbt "$PSBT_CIERRE" | jq -r '.psbt')
ok "Firma de Alice añadida."

# 3. Firmar la PSBT por Bob
log "Bob revisa y aplica su firma (2/2)..."
PSBT_CIERRE_BOB=$(bcli -rpcwallet=Bob walletprocesspsbt "$PSBT_CIERRE_ALICE" | jq -r '.psbt')
ok "Firma de Bob añadida."

# 4. Extraer y transmitir la transacción completamente firmada
log "Finalizando (finalizapsbt) y transmitiendo (sendrawtransaction) la transacción de cierre..."
TX_HEX_CIERRE=$(bcli finalizepsbt "$PSBT_CIERRE_BOB" | jq -r '.hex')
TXID_CIERRE=$(bcli sendrawtransaction "$TX_HEX_CIERRE")
ok "Multisig liquidado y transmitido a la red - TXID: $TXID_CIERRE"

# Minamos para confirmar esta última transacción
NUM_BLOC=1
log "Minando $NUM_BLOC bloque(s) para confirmar los movimientos..."
minar_y_confirmar $NUM_BLOC

# 5. Imprimir los saldos finales de Alice y Bob
echo
log "=== SALDOS FINALES TRAS EL CIERRE ==="
imprimir_saldo "Miner"
imprimir_saldo "Alice"
imprimir_saldo "Bob"
imprimir_saldo "Multisig"
