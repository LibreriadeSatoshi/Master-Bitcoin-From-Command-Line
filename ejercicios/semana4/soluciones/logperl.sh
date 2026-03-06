#!/bin/bash

###### Enunciado del Problema
# En el siguiente ejercicio, pasaremos por un flujo de trabajo en el que un empleado recibe su salario de un empleador, pero solo después de que haya transcurrido cierto tiempo. El empleado también lo celebra y realiza un gasto de OP_RETURN para que todo el mundo sepa que ya no está desempleado. A continuación haremos un timelock realtivo.
###############

set -euo pipefail

# --- VARIABLES DE CONFIGURACIÓN ---
BITCOIN_VERSION="29.0"
BITCOIN_USER="bitcoin"
BITCOIN_DATA_DIR="/home/bitcoin"
BITCOIN_CONF_DIR="${BITCOIN_DATA_DIR}/.bitcoin"

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
log() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
ok()  { echo -e "${GREEN}[OK]${NC}   $1" >&2; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
# La función error ahora acepta el mensaje de error del servidor como segundo parámetro opcional
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    if [ -n "${2:-}" ]; then
        echo -e "${RED}--- RAW SERVER OUTPUT ---${NC}" >&2
        # Respetamos los saltos de línea originales del servidor
        echo -e "${RED}$2${NC}" >&2
        echo -e "${RED}-------------------------${NC}" >&2
    fi
    exit 1
}

# --- COMPROBACIÓN DE DEPENDENCIAS ---
if ! command -v jq &> /dev/null; then
    error "El comando 'jq' no está instalado. Es necesario para parsear JSON. Instálalo con: sudo apt install jq"
fi

#### PRE: Para empezar de 0, el script primero parará y borrará cualquier rastro de blockchain
reinicio_de_0() {
    log "Gestionando proceso bitcoind..."
    
    if pgrep -x "bitcoind" > /dev/null; then
        warn "Deteniendo nodo existente..."
        bcli stop >/dev/null 2>&1 || true
        sleep 2
    fi

    if [ -d "${BITCOIN_CONF_DIR}/regtest" ]; then
        log "Borrando blockchain antigua (Regtest Reset)..."
        rm -rf "${BITCOIN_CONF_DIR}/regtest"
    fi

    log "Iniciando nodo limpio..."
    bitcoind -daemon > /dev/null
    sleep 2 
}

# 1. Crea tres monederos: Miner, Empleado y Empleador.
crear_wallets() {
    log "Punto 1: Creando Wallets..."
    
    crear_simple() {
        local WNAME=$1
        local OUTPUT
        if ! OUTPUT=$(bcli -named createwallet wallet_name="$WNAME" 2>&1); then
            error "Fallo al crear wallet '$WNAME'." "$OUTPUT"
        fi
        ok "Wallet '$WNAME' creada."
    }

    crear_simple "Miner"
    crear_simple "Empleado"
    crear_simple "Empleador"
}

# Función centralizada para minar bloques con validaciones de seguridad
# Verificando que estemos en regtest
minar_bloques() {
    local num_blocks=${1:-1}
    # Por defecto, los bloques se minan a favor del "Miner" si no se especifica otra cartera
    local wallet_name=${2:-"Miner"} 
    local OUTPUT

    log "Verificando que estamos en 'regtest' antes de minar..."
    if ! OUTPUT=$(bcli getblockchaininfo 2>&1); then
        error "Fallo al obtener info de la blockchain." "$OUTPUT"
    fi
    local current_chain=$(echo "$OUTPUT" | jq -r '.chain')

    if [ "$current_chain" != "regtest" ]; then
        error "El nodo no está en la red 'regtest'." "Cadena detectada: $current_chain"
    fi

    log "Generando dirección de recompensa para la wallet '$wallet_name'..."
    local address
    if ! address=$(bcli -rpcwallet="$wallet_name" getnewaddress "Recompensa_Minería" 2>&1); then
        error "Fallo al generar la dirección para la wallet '$wallet_name'."
    fi

    log "Minando $num_blocks bloque(s)..."
    if ! OUTPUT=$(bcli generatetoaddress "$num_blocks" "$address" 2>&1); then
        error "Fallo al ejecutar la orden de minería." "$OUTPUT"
    fi
    
    ok "Se han minado $num_blocks bloque(s) con éxito."
}

# Funcion preparar_envio:
#   Recibe: ORIGEN, DESTINO, MONTO, LOCKTIME (Opcional), OP_RETURN_MSG (Opcional)
#   Devuelve: TXID
preparar_envio() {
    local ORIGEN=$1
    local DESTINO=$2
    local MONTO=$3
    local LOCKTIME=${4:-0}
    local MENSAJE_OP_RETURN=${5:-}
    local OUTPUT

    log "Construyendo transacción: $MONTO BTC de '$ORIGEN' a '$DESTINO' (nLockTime=$LOCKTIME)..."

    local ADDR_DESTINO
    if ! ADDR_DESTINO=$(bcli -rpcwallet="$DESTINO" getnewaddress "Cobro_$ORIGEN" 2>&1); then
        error "Fallo al obtener dirección de destino." "$ADDR_DESTINO"
    fi

    local OUTPUTS_JSON
    if [ -n "$MENSAJE_OP_RETURN" ]; then
        log "Codificando mensaje OP_RETURN a Hexadecimal..."
        # Convertimos texto plano a Hex sin saltos de línea
        local HEX_MSG=$(echo -n "$MENSAJE_OP_RETURN" | xxd -p | tr -d '\n')
        
        # El JSON ahora tiene 2 salidas: El pago al destino, y la data OP_RETURN
        OUTPUTS_JSON="[{\"$ADDR_DESTINO\":$MONTO}, {\"data\":\"$HEX_MSG\"}]"
    else
        # Envío normal sin mensaje
        OUTPUTS_JSON="[{\"$ADDR_DESTINO\":$MONTO}]"
    fi

    local RAW_TX
    if ! RAW_TX=$(bcli -rpcwallet="$ORIGEN" createrawtransaction "[]" "$OUTPUTS_JSON" "$LOCKTIME" 2>&1); then
        error "Fallo al crear la transacción cruda." "$RAW_TX"
    fi

    local FUND_RESULT
    if ! FUND_RESULT=$(bcli -rpcwallet="$ORIGEN" fundrawtransaction "$RAW_TX" 2>&1); then
        error "Fallo al fondear la transacción." "$FUND_RESULT"
    fi
    local FUNDED_TX=$(echo "$FUND_RESULT" | jq -r '.hex')

    local SIGN_RESULT
    if ! SIGN_RESULT=$(bcli -rpcwallet="$ORIGEN" signrawtransactionwithwallet "$FUNDED_TX" 2>&1); then
        error "Fallo al ejecutar la rutina de firma." "$SIGN_RESULT"
    fi
    
    local IS_COMPLETE=$(echo "$SIGN_RESULT" | jq -r '.complete')
    if [ "$IS_COMPLETE" != "true" ]; then
        error "La transacción se firmó parcialmente." "$SIGN_RESULT"
    fi

    echo "$(echo "$SIGN_RESULT" | jq -r '.hex')"
}

# Funcion transmitir_tx
#   Recibe: HEX_TX (Transacción firmada en hexadecimal)
#   Devuelve: TXID
transmitir_tx() {
    local HEX_TX=$1
    local RESULTADO

    log "Transmitiendo transacción a la mempool..."
    if ! RESULTADO=$(bcli sendrawtransaction "$HEX_TX" 2>&1); then
        warn "La transacción fue rechazada. Respuesta RAW del servidor:"
        # Usamos echo para imprimir el error RAW, enviándolo a stderr con color rojo
	# No lo hacemos con la funcion "error" porque esta conlleva un "exit"
        echo -e "${RED}$RESULTADO${NC}" >&2
        return 1
    fi
    
    echo "$RESULTADO"
}

# Funcion preparar_envio_relativo:
#   Aplica Coin Control para inyectar un Timelock Relativo (BIP68) en el nSequence.
#   Recibe: ORIGEN, DESTINO, MONTO, BLOCKS_DELAY
preparar_envio_relativo() {
    local ORIGEN=$1
    local DESTINO=$2
    local MONTO=$3
    local BLOCKS_DELAY=$4

    log "Construyendo TX con Timelock Relativo ($BLOCKS_DELAY bloques) de '$ORIGEN' a '$DESTINO'..."

    local ADDR_DESTINO
    if ! ADDR_DESTINO=$(bcli -rpcwallet="$DESTINO" getnewaddress "Timelock_Relativo_$ORIGEN" 2>&1); then
        error "Fallo al obtener dirección de destino." "$ADDR_DESTINO"
    fi

    # --- Coin Control ---
    # Listamos los billetes disponibles. Usamos jq para ordenarlos por confirmaciones 
    # de menor a mayor y elegimos el billete MÁS RECIENTE que tenga saldo suficiente.
    # Esto garantiza que el bloqueo relativo tenga efecto.
    local UNSPENT
    if ! UNSPENT=$(bcli -rpcwallet="$ORIGEN" listunspent 1 9999999 2>&1); then
        error "Fallo al listar UTXOs." "$UNSPENT"
    fi
    
    local UTXO=$(echo "$UNSPENT" | jq --arg m "$MONTO" -r 'sort_by(.confirmations) | [.[] | select(.amount >= ($m|tonumber))][0]')
    if [ "$UTXO" == "null" ]; then
        error "No hay un UTXO individual con saldo suficiente en '$ORIGEN'."
    fi

    local TXID=$(echo "$UTXO" | jq -r '.txid')
    local VOUT=$(echo "$UTXO" | jq -r '.vout')
    local CONFS=$(echo "$UTXO" | jq -r '.confirmations')

    log "UTXO seleccionado: $TXID (Vout: $VOUT) | Edad del billete: $CONFS confirmaciones."

    # --- INYECCIÓN DEL TIMELOCK RELATIVO ---
    # BIP68: Asignamos el BLOCKS_DELAY al campo 'sequence' del input.
    local INPUTS_JSON="[{\"txid\":\"$TXID\",\"vout\":$VOUT,\"sequence\":$BLOCKS_DELAY}]"
    local OUTPUTS_JSON="[{\"$ADDR_DESTINO\":$MONTO}]"

    local RAW_TX
    if ! RAW_TX=$(bcli -rpcwallet="$ORIGEN" createrawtransaction "$INPUTS_JSON" "$OUTPUTS_JSON" 2>&1); then
        error "Fallo al crear la transacción relativa." "$RAW_TX"
    fi

    # Fondear añade el cambio (vueltas) automáticamente sin pisar nuestro input personalizado.
    local FUND_RESULT
    if ! FUND_RESULT=$(bcli -rpcwallet="$ORIGEN" fundrawtransaction "$RAW_TX" 2>&1); then
        error "Fallo al fondear la transacción relativa." "$FUND_RESULT"
    fi
    local FUNDED_TX=$(echo "$FUND_RESULT" | jq -r '.hex')

    local SIGN_RESULT
    if ! SIGN_RESULT=$(bcli -rpcwallet="$ORIGEN" signrawtransactionwithwallet "$FUNDED_TX" 2>&1); then
        error "Fallo al ejecutar la firma." "$SIGN_RESULT"
    fi
    
    local IS_COMPLETE=$(echo "$SIGN_RESULT" | jq -r '.complete')
    if [ "$IS_COMPLETE" != "true" ]; then
        error "Firma parcial en TX relativa." "$SIGN_RESULT"
    fi

    echo "$(echo "$SIGN_RESULT" | jq -r '.hex')"
}


#### ==========================================
#### EJECUCION PRINCIPAL DEL PROGRAMA
#### ==========================================

reinicio_de_0
crear_wallets

echo
log "Punto 2.a: Fondeando cartera 'Miner'..."
minar_bloques 104 "Miner"
balance_miner=$(bcli -rpcwallet="Miner" getbalance)
ok "Saldo gastable actual de 'Miner': $balance_miner BTC"

log "Punto 2.b: Fondeando cartera 'Empleador'..."
TX_EMPLEADOR_HEX=$(preparar_envio "Miner" "Empleador" 50)
TXID_EMPLEADOR=$(transmitir_tx "$TX_EMPLEADOR_HEX")
ok "Transacción de 50 BTC enviada a la mempool. TXID: $TXID_EMPLEADOR"

log "Minando bloques para confirmar el fondeo del Empleador..."
minar_bloques 3 "Miner"
balance_empleador=$(bcli -rpcwallet="Empleador" getbalance)
ok "El saldo actual del Empleador es: $balance_empleador BTC"

echo
log "Punto 3 y 4: Transacción de salario con Timelock absoluto (Bloque 500)."
TX_SALARIO_HEX=$(preparar_envio "Empleador" "Empleado" 40 500)
ok "Transacción cruda firmada con nLockTime=500."

echo
log "Punto 5: Informa en un comentario qué sucede cuando intentas transmitir esta transacción."
if ! TXID=$(transmitir_tx "$TX_SALARIO_HEX"); then
    ok "Éxito comprobado: La red bloqueó la transacción correctamente."
    ok "=========================================================================="
    ok "🧠 INFO: ¿Por qué la mempool rechaza esta transacción?"
    ok "   -> Tiene un Timelock Absoluto (nLockTime = 500)."
    ok "   -> Las reglas de consenso prohíben estrictamente propagar, validar o"
    ok "      minar cualquier transacción cuyo nLockTime sea mayor a la altura"
    ok "      actual de la blockchain. Es criptográficamente 'non-final'."
    ok "   "
    ok "   DIFERENCIA CLAVE CON LOS BLOQUEOS POR SCRIPT (OP_CLTV / OP_CSV):"
    ok "   -> En un bloqueo por Script, la transacción que fondea el UTXO SÍ entra"
    ok "      a la mempool y se mina de inmediato. Lo que la red bloquea es el"
    ok "      intento de GASTAR ese UTXO en el futuro."
    ok " -> El nLockTime, en cambio, bloquea la transacción entera desde su origen."
    ok "=========================================================================="
else
    error "Fallo de seguridad: La transacción se envió antes de tiempo." "TXID: $TXID"
fi

echo
log "Punto 6: Mina hasta el bloque 500 y transmite la transacción."
BLOQUE_ACTUAL=$(bcli getblockcount)
BLOQUES_FALTANTES=$((500 - BLOQUE_ACTUAL))
log "  500 - $BLOQUE_ACTUAL (Bloque actual)"
if [ "$BLOQUES_FALTANTES" -gt 0 ]; then
    minar_bloques "$BLOQUES_FALTANTES" "Miner"
fi

log "Intentando transmitir el salario en el bloque 500..."
if ! TXID_SALARIO=$(transmitir_tx "$TX_SALARIO_HEX"); then
    error "La transacción falló incluso después de alcanzar el bloque 500." "Transmisión fallida."
fi
ok "¡Salario aceptado por la mempool! TXID: $TXID_SALARIO"

echo
log "Punto 7: Imprime los saldos finales del Empleado y Empleador."
balance_empleador_mempool=$(bcli -rpcwallet="Empleador" getbalance)
balance_empleado_mempool=$(bcli -rpcwallet="Empleado" getbalance)
ok "ANTES de minar (0 confs) -> Empleador: $balance_empleador_mempool BTC | Empleado: $balance_empleado_mempool BTC"
log "Minando 1 bloque para confirmar el salario en la blockchain..."
# Al ejecutar esto, la transacción sale de la mempool y entra en la cadena
minar_bloques 1 "Miner"
balance_empleador_final=$(bcli -rpcwallet="Empleador" getbalance)
balance_empleado_final=$(bcli -rpcwallet="Empleado" getbalance)
ok "DESPUÉS de minar (1 conf)  -> Empleador: $balance_empleador_final BTC | Empleado: $balance_empleado_final BTC"

echo
echo "################################"
log "FASE 2: GASTAR DESDE EL TIMELOCK"

log "Punto 2.1: Crea una transacción de gasto en la que el Empleado gaste los fondos a una nueva dirección de monedero del Empleado."
log "Punto 2.2: Agrega una salida OP_RETURN en la transacción de gasto con los datos de cadena 'He recibido mi salario, ahora soy rico'."
MENSAJE="He recibido mi salario, ahora soy rico"

# El Locktime es 0 (sin bloqueo), y el quinto parámetro es nuestro mensaje.
TX_OP_RETURN_HEX=$(preparar_envio "Empleado" "Empleado" 10 0 "$MENSAJE")

echo
log "Punto 2.3: Extrae y transmite la transacción completamente firmada."
if ! TXID_GASTO=$(transmitir_tx "$TX_OP_RETURN_HEX"); then
    error "No se pudo transmitir el gasto con OP_RETURN."
fi
ok "¡Gasto con OP_RETURN aceptado en la mempool! TXID: $TXID_GASTO"

echo
log "Punto 2.4: Imprime los saldos finales del Empleado y Empleador."
log "Minando 1 bloque para confirmar el OP_RETURN en la blockchain..."
minar_bloques 1 "Miner"
balance_empleador_final=$(bcli -rpcwallet="Empleador" getbalance)
balance_empleado_final=$(bcli -rpcwallet="Empleado" getbalance)
ok "Saldo final Empleador: $balance_empleador_final BTC"
ok "Saldo final Empleado:  $balance_empleado_final BTC (menos la comisión de red por su gasto)"

echo
log "EXTRA: Leyendo el mensaje OP_RETURN desde la Blockchain."

# 1. Obtenemos la transacción directamente del ledger (pasando 'true' para que el nodo nos la devuelva decodificada en JSON)
TX_JSON=$(bcli getrawtransaction "$TXID_GASTO" true)

# 2. Navegamos por el JSON: buscamos la salida (vout) de tipo "nulldata" (OP_RETURN),
# extraemos su campo 'asm' (ensamblador) que se ve así: "OP_RETURN 4865...", 
# y con awk nos quedamos solo con la segunda columna (el texto hexadecimal).
HEX_GRABADO=$(echo "$TX_JSON" | jq -r '.vout[].scriptPubKey | select(.type=="nulldata") | .asm' | awk '{print $2}')

# 3. Revertimos el proceso: de Hexadecimal a texto legible (ASCII) usando xxd en modo reverso (-r)
MENSAJE_DECODIFICADO=$(echo "$HEX_GRABADO" | xxd -p -r)

log "Analizando la transacción $TXID_GASTO..."
ok "Hexadecimal incrustado encontrado: $HEX_GRABADO"
ok "Mensaje público revelado: '${MENSAJE_DECODIFICADO}'"

echo
echo "################################"
log "FASE 3: CONFIGURAR UN TIMELOCK RELATIVO"

log "Punto 3.1: Crear TX donde Empleador paga 1 BTC a Miner con timelock relativo de 10 bloques."
TX_RELATIVA_HEX=$(preparar_envio_relativo "Empleador" "Miner" 1 10)
ok "Transacción cruda con Timelock Relativo (nSequence=10) firmada."

echo
log "Punto 3.2: Informar en la salida qué sucede al intentar difundir la transacción."
log "Intentando transmitir la transacción relativa inmediatamente..."

if ! TXID_RELATIVO=$(transmitir_tx "$TX_RELATIVA_HEX"); then
    ok "Éxito comprobado: La red rechazó la transacción por el bloqueo relativo."
    ok "=========================================================================="
    ok "🧠 INFO: ¿Por qué falla con el error 'non-BIP68-final'?"
    ok "   -> Al contrario que el nLockTime (que mira el bloque actual de la red),"
    ok "      el Timelock Relativo (nSequence) evalúa la EDAD de la moneda de origen."
    ok "   -> Le indicamos al protocolo: 'Este UTXO exacto que intento gastar debe"
    ok "      tener al menos 10 bloques de antigüedad (confirmaciones) para ser válido'."
    ok "   -> Como acabamos de seleccionar un billete que se minó hace menos de"
    ok "      10 bloques (probablemente el cambio de la Fase 1), la mempool"
    ok "      lo escupe porque 'Aún no tiene la edad suficiente' para ser gastado."
    ok "=========================================================================="
else
    error "Fallo de seguridad: La transacción relativa se envió antes de tiempo." "TXID: $TXID_RELATIVO"
fi

echo
echo "################################"
log "FASE 4: GASTAR DESDE EL TIMELOCK RELATIVO"

log "Punto 4.1: Generar 10 bloques adicionales."
# Minamos los 10 bloques para que el UTXO alcance la "edad" requerida por el nSequence
minar_bloques 10 "Miner"
ok "10 bloques generados. El UTXO retenido ya ha madurado lo suficiente."

echo
log "Punto 4.2: Difundir la segunda transacción y confirmarla generando un bloque más."
log "Volviendo a intentar transmitir la transacción relativa..."

# Ahora la mempool sí debe aceptarla porque se cumple la condición de BIP68
if ! TXID_RELATIVO_FINAL=$(transmitir_tx "$TX_RELATIVA_HEX"); then
    error "La transacción relativa falló incluso después de minar 10 bloques." "Transmisión fallida."
fi
ok "Transacción relativa aceptada por la red. TXID: $TXID_RELATIVO_FINAL"

log "Minando 1 bloque extra para confirmar la transacción en la blockchain..."
minar_bloques 1 "Miner"

echo
log "Punto 4.3: Informar el saldo de Empleador."
balance_empleador_bip68=$(bcli -rpcwallet="Empleador" getbalance)
ok "Saldo definitivo del Empleador: $balance_empleador_bip68 BTC"
