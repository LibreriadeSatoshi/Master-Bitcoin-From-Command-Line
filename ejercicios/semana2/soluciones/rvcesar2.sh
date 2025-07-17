#!/bin/bash

# ==============================================================================
# Script para la configuración y uso de Bitcoin Core en modo RegTest con RBF
# Creado por: rvcesar
# ==============================================================================

# --- Variables de Configuración ---
BITCOIN_VERSION="29.0" # Puedes cambiar esto a la última versión si es necesario
ARCH="x86_64-linux-gnu"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz"
CHECKSUM_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
SIGNATURE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc"
DATA_DIR="$HOME/.bitcoin-rbf" # Usamos un directorio diferente para evitar conflictos
CONF_FILE="$DATA_DIR/bitcoin.conf"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

# --- Funciones Auxiliares ---

# Función para imprimir encabezados
print_header() {
  echo ""
  echo "=============================================================================="
  echo " $1"
  echo "=============================================================================="
  echo ""
}

# Función para detener bitcoind al finalizar o en caso de error
cleanup() {
  print_header "DETENIENDO BITCOIN CORE"
  if bitcoin-cli -datadir="$DATA_DIR" ping > /dev/null 2>&1; then
    echo "Deteniendo bitcoind..."
    bitcoin-cli -datadir="$DATA_DIR" stop
    # Esperar hasta que bitcoind se detenga por completo, con un timeout
    timeout 30 bash -c "while bitcoin-cli -datadir='$DATA_DIR' ping > /dev/null 2>&1; do sleep 1; done"
    echo "bitcoind detenido."
  else
    echo "bitcoind no parece estar en ejecución."
  fi
  # Limpiar archivos descargados
  rm -f bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz SHA256SUMS SHA256SUMS.asc
  # Limpiar directorio guix.sigs
  rm -rf guix.sigs
}

# Atrapa la salida del script para ejecutar la limpieza
trap cleanup EXIT

# --- Inicio del Script ---

---
## VERIFICANDO DEPENDENCIAS
print_header "VERIFICANDO DEPENDENCIAS"
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' no está instalado. Por favor, instálalo para continuar (ej. sudo apt-get install jq)."
    exit 1
fi
if ! command -v gpg &> /dev/null; then
    echo "Error: 'gpg' no está instalado. Por favor, instálalo para continuar (ej. sudo apt-get install gpg)."
    exit 1
fi
if ! command -v git &> /dev/null; then
    echo "Error: 'git' no está instalado. Por favor, instálalo para continuar (ej. sudo apt-get install git)."
    exit 1
fi
echo "Dependencias 'jq', 'gpg' y 'git' encontradas."

---
## PASO 1: DESCARGA, VERIFICACIÓN E INICIO DE BITCOIN CORE

print_header "PASO 1: DESCARGA, VERIFICACIÓN E INICIO DE BITCOIN CORE"

# Descarga de binarios, hashes y firmas
echo "Descargando Bitcoin Core v${BITCOIN_VERSION}..."
wget -q --show-progress -O bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz "$BITCOIN_URL"
echo "Descargando archivos de suma de verificación (checksums)..."
wget -q -O SHA256SUMS "$CHECKSUM_URL"
echo "Descargando firmas..."
wget -q -O SHA256SUMS.asc "$SIGNATURE_URL"

# Verificación de la integridad del archivo
echo -e "\nVerificando la suma de verificación (checksum) del archivo descargado..."
sha256sum --ignore-missing -c SHA256SUMS | grep "bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz: OK"
if [ $? -ne 0 ]; then
  echo "Error: La verificación de la suma de verificación falló. El archivo puede estar corrupto."
  exit 1
fi
echo "Suma de verificación correcta."

# Verificación de la firma GPG
echo -e "\nImportando las claves de firma de los desarrolladores de Bitcoin Core..."
if [ -d "guix.sigs" ]; then
    echo "Directorio 'guix.sigs' ya existe, actualizando..."
    (cd guix.sigs && git pull)
else
    echo "Clonando repositorio 'guix.sigs'..."
    git clone https://github.com/bitcoin-core/guix.sigs
fi

# Import keys, suppressing warnings for already imported keys
# Only import if the key isn't already present to avoid "already imported" warnings
for key_file in guix.sigs/builder-keys/*.gpg; do
    key_id=$(gpg --with-colons "$key_file" 2>/dev/null | awk -F: '/^pub/{print $5}' | head -n 1)
    if [ -n "$key_id" ] && ! gpg --list-keys "$key_id" > /dev/null 2>&1; then
        gpg --batch --import "$key_file" 2>/dev/null
    fi
done

echo -e "\nVerificando la firma GPG del archivo de sumas de verificación..."
if gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -q "Good signature"; then
  echo -e "\n\e[32mVerificación exitosa de la firma binaria.\e[0m"
else
  echo "Error: La firma GPG no es válida o no se pudo verificar. ¡El archivo de sumas de verificación podría haber sido manipulado!"
  echo "Asegúrate de que las claves GPG de los desarrolladores estén actualizadas."
  exit 1
fi

# Extracción y configuración del PATH
echo -e "\nExtrayendo los binarios..."
tar -xzf bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz
export PATH="$PWD/bitcoin-${BITCOIN_VERSION}/bin:$PATH"
echo "PATH actualizado para la sesión actual."

# Crear directorio .bitcoin-rbf y archivo de configuración
echo "Creando el directorio de datos en $DATA_DIR..."
mkdir -p "$DATA_DIR"

echo "Creando el archivo de configuración bitcoin.conf..."
cat > "$CONF_FILE" << EOF
# Configuraciones para modo RegTest
regtest=1
fallbackfee=0.0001
server=1
txindex=1
# Enable RBF for created transactions by default for testing
walletrbf=1
EOF

# Iniciar bitcoind
echo "Iniciando bitcoind en modo demonio..."
bitcoind -datadir="$DATA_DIR" -daemon
sleep 5

echo "Verificando que bitcoind esté en ejecución..."
# Loop to wait for bitcoind to be ready
for i in {1..10}; do
    bitcoin-cli -datadir="$DATA_DIR" ping > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "bitcoind está en ejecución."
        break
    else
        echo "Esperando a bitcoind... ($i/10)"
        sleep 2
    fi
    if [ $i -eq 10 ]; then
        echo "Error: bitcoind no se inició a tiempo. Revisar los logs en $DATA_DIR/regtest/debug.log"
        exit 1
    fi
done

---
## PASO 2: CREACIÓN Y FONDEO DE BILLETERAS

print_header "PASO 2: CREANDO Y FONDEANDO BILLETERAS"

# Crear las billeteras
echo "Creando billetera '$MINER_WALLET'..."
bitcoin-cli -datadir="$DATA_DIR" createwallet "$MINER_WALLET" > /dev/null

echo "Creando billetera '$TRADER_WALLET'..."
bitcoin-cli -datadir="$DATA_DIR" createwallet "$TRADER_WALLET" > /dev/null

# Fondear la billetera Miner con 3 recompensas de bloque (150 BTC)
echo "Generando 301 bloques para fondear la billetera '$MINER_WALLET' (3 recompensas de 50 BTC + 100 confirmaciones por cada una)..."
MINER_ADDRESS=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET getnewaddress "Recompensa de Mineria")
# We mine 101 blocks for the first 50 BTC reward to mature.
# Then 100 more for the second, and 100 more for the third.
# Total: 101 + 100 + 100 = 301 blocks.
bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET generatetoaddress 301 "$MINER_ADDRESS" > /dev/null

MINER_BALANCE=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET getbalance)
echo -e "Saldo inicial de la billetera '$MINER_WALLET': \e[33m$MINER_BALANCE BTC\e[0m"

# Verificar que el saldo es de 150 BTC
if (( $(echo "$MINER_BALANCE < 150" | bc -l) )); then
    echo "Error: El saldo de la billetera Miner es insuficiente. Se esperaba al menos 150 BTC."
    exit 1
fi

# Obtener UTXOs de 50 BTC para la billetera Miner
echo "Obteniendo UTXOs de 50 BTC de la billetera '$MINER_WALLET'..."

# Define the JSON query options as a single object for listunspent
JSON_QUERY_OPTIONS='{"minimumAmount":49.99999999,"maximumAmount":50.00000001}'

# Pass the JSON_QUERY_OPTIONS correctly by explicitly providing empty strings for unused arguments
UTXOS_50_BTC=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet="$MINER_WALLET" listunspent 0 9999999 "[]" "false" "$JSON_QUERY_OPTIONS" | jq -c '[.[] | select(.amount == 50 and .confirmations >= 100)]')

# Validate that we got enough UTXOs
NUM_UTXOS=$(echo "$UTXOS_50_BTC" | jq 'length')
if [ "$NUM_UTXOS" -lt 2 ]; then
    echo "Error: No se encontraron suficientes UTXOs de 50 BTC maduras. Asegúrate de haber minado suficientes bloques."
    echo "UTXOs encontradas: $UTXOS_50_BTC"
    exit 1
fi

INPUT_TXID_0=$(echo "$UTXOS_50_BTC" | jq -r '.[0].txid')
INPUT_VOUT_0=$(echo "$UTXOS_50_BTC" | jq -r '.[0].vout')

INPUT_TXID_1=$(echo "$UTXOS_50_BTC" | jq -r '.[1].txid')
INPUT_VOUT_1=$(echo "$UTXOS_50_BTC" | jq -r '.[1].vout')

echo "UTXO 1: txid=$INPUT_TXID_0, vout=$INPUT_VOUT_0"
echo "UTXO 2: txid=$INPUT_TXID_1, vout=$INPUT_VOUT_1"

# Obtener direcciones para las salidas
TRADER_RECEIVE_ADDRESS=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$TRADER_WALLET getnewaddress "Pago a Trader")
MINER_CHANGE_ADDRESS=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET getnewaddress "Cambio de Miner")

# Obtener los scriptPubKey de las direcciones
TRADER_SCRIPT_PUBKEY=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$TRADER_WALLET getaddressinfo "$TRADER_RECEIVE_ADDRESS" | jq -r '.scriptPubKey')
MINER_SCRIPT_PUBKEY=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET getaddressinfo "$MINER_CHANGE_ADDRESS" | jq -r '.scriptPubKey')

---
## PASO 3: CREACIÓN Y TRANSMISIÓN DE LA TRANSACCIÓN PARENT (RBF habilitado)

print_header "PASO 3: CREANDO Y TRANSMITIENDO LA TRANSACCIÓN PARENT (RBF)"

# Create the raw transaction (parent)
echo "Creando la transacción parent con RBF habilitado..."
RAW_TX_PARENT_HEX=$(bitcoin-cli -datadir="$DATA_DIR" createrawtransaction \
  "[{\"txid\": \"$INPUT_TXID_0\", \"vout\": $INPUT_VOUT_0, \"sequence\": 0}, {\"txid\": \"$INPUT_TXID_1\", \"vout\": $INPUT_VOUT_1, \"sequence\": 0}]" \
  "{\"${TRADER_RECEIVE_ADDRESS}\": 70, \"${MINER_CHANGE_ADDRESS}\": 29.99999}" \
)

if [ -z "$RAW_TX_PARENT_HEX" ]; then
    echo "Error: Falló la creación de la transacción raw parent."
    exit 1
fi
echo "Transacción Parent Raw (HEX): $RAW_TX_PARENT_HEX"

# Firmar la transacción parent
echo "Firmando la transacción parent..."
SIGNED_TX_PARENT=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET signrawtransactionwithwallet "$RAW_TX_PARENT_HEX" | jq -r '.hex')

if [ -z "$SIGNED_TX_PARENT" ]; then
    echo "Error: Falló la firma de la transacción parent."
    exit 1
fi

# Transmitir la transacción parent (sin confirmar)
echo "Transmitiendo la transacción parent (sin confirmar)..."
PARENT_TXID=$(bitcoin-cli -datadir="$DATA_DIR" sendrawtransaction "$SIGNED_TX_PARENT")
if [ $? -ne 0 ]; then
    echo "Error: Falló la transmisión de la transacción parent."
    exit 1
fi
echo "TXID de la transacción Parent: $PARENT_TXID"

sleep 2 # Give time for the transaction to propagate in the mempool

---
## PASO 4: CONSULTA AL MEMPOOL DE LA TRANSACCIÓN PARENT

print_header "PASO 4: CONSULTANDO LA TRANSACCIÓN PARENT EN EL MEMPOOL"

MEMPOOL_ENTRY_PARENT=$(bitcoin-cli -datadir="$DATA_DIR" getmempoolentry "$PARENT_TXID")

if [ -z "$MEMPOOL_ENTRY_PARENT" ]; then
    echo "Error: No se encontró la transacción parent en el mempool. TXID: $PARENT_TXID"
    exit 1
fi

# Extract details for the JSON
DECODED_PARENT_TX=$(bitcoin-cli -datadir="$DATA_DIR" decoderawtransaction "$SIGNED_TX_PARENT")

PARENT_INPUT_TXID_0=$(echo "$DECODED_PARENT_TX" | jq -r '.vin[0].txid')
PARENT_INPUT_VOUT_0=$(echo "$DECODED_PARENT_TX" | jq -r '.vin[0].vout')
PARENT_INPUT_TXID_1=$(echo "$DECODED_PARENT_TX" | jq -r '.vin[1].txid')
PARENT_INPUT_VOUT_1=$(echo "$DECODED_PARENT_TX" | jq -r '.vin[1].vout')

PARENT_FEE=$(echo "$MEMPOOL_ENTRY_PARENT" | jq -r '.fees.base')
PARENT_WEIGHT=$(echo "$MEMPOOL_ENTRY_PARENT" | jq -r '.weight')

# Iterate outputs to get script_pubkey and amount
TRADER_AMOUNT=$(echo "$DECODED_PARENT_TX" | jq -r ".vout[] | select(.scriptPubKey.address==\"$TRADER_RECEIVE_ADDRESS\") | .value")
MINER_AMOUNT=$(echo "$DECODED_PARENT_TX" | jq -r ".vout[] | select(.scriptPubKey.address==\"$MINER_CHANGE_ADDRESS\") | .value")

# Create the JSON (ensure all numerical variables are passed as --argjson)
TRANSACTION_PARENT_INFO=$(jq -n \
  --arg txid0 "$PARENT_INPUT_TXID_0" \
  --argjson vout0 "$PARENT_INPUT_VOUT_0" \
  --arg txid1 "$PARENT_INPUT_TXID_1" \
  --argjson vout1 "$PARENT_INPUT_VOUT_1" \
  --arg script_pubkey_miner "$MINER_SCRIPT_PUBKEY" \
  --argjson amount_miner "$MINER_AMOUNT" \
  --arg script_pubkey_trader "$TRADER_SCRIPT_PUBKEY" \
  --argjson amount_trader "$TRADER_AMOUNT" \
  --argjson fees "$PARENT_FEE" \
  --argjson weight "$PARENT_WEIGHT" \
  '{
    "input": [
      {
        "txid": $txid0,
        "vout": $vout0
      },
      {
        "txid": $txid1,
        "vout": $vout1
      }
    ],
    "output": [
      {
        "script_pubkey": $script_pubkey_miner,
        "amount": $amount_miner
      },
      {
        "script_pubkey": $script_pubkey_trader,
        "amount": $amount_trader
      }
    ],
    "Fees": $fees,
    "Weight": $weight
  }')

echo "Detalles de la transacción Parent en formato JSON:"
echo "$TRANSACTION_PARENT_INFO" | jq .

---
## PASO 5: CREACIÓN Y TRANSMISIÓN DE LA TRANSACCIÓN CHILD

print_header "PASO 5: CREANDO Y TRANSMITIENDO LA TRANSACCIÓN CHILD"

# Obtener la salida del cambio de Miner de la transacción parent
CHILD_INPUT_VOUT=$(echo "$DECODED_PARENT_TX" | jq -r ".vout[] | select(.scriptPubKey.address==\"$MINER_CHANGE_ADDRESS\") | .n")

echo "Input para la transacción Child: txid=$PARENT_TXID, vout=$CHILD_INPUT_VOUT"

# Crear nueva dirección para Miner para la salida de la transacción child
NEW_MINER_ADDRESS=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET getnewaddress "Nueva Direccion Miner")
echo "Nueva dirección de Miner para la transacción Child: $NEW_MINER_ADDRESS"

# Calculate the output amount for the child transaction (29.99998 BTC)
CHILD_OUTPUT_AMOUNT=29.99998

# Create the raw transaction (child)
echo "Creando la transacción child..."
RAW_TX_CHILD_HEX=$(bitcoin-cli -datadir="$DATA_DIR" createrawtransaction \
  "[{\"txid\": \"$PARENT_TXID\", \"vout\": $CHILD_INPUT_VOUT}]" \
  "{\"${NEW_MINER_ADDRESS}\": $CHILD_OUTPUT_AMOUNT}" \
)

if [ -z "$RAW_TX_CHILD_HEX" ]; then
    echo "Error: Falló la creación de la transacción raw child."
    exit 1
fi
echo "Transacción Child Raw (HEX): $RAW_TX_CHILD_HEX"

# Firmar la transacción child
echo "Firmando la transacción child..."
SIGNED_TX_CHILD=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET signrawtransactionwithwallet "$RAW_TX_CHILD_HEX" | jq -r '.hex')

if [ -z "$SIGNED_TX_CHILD" ]; then
    echo "Error: Falló la firma de la transacción child."
    exit 1
fi

# Transmitir la transacción child
echo "Transmitiendo la transacción child..."
CHILD_TXID=$(bitcoin-cli -datadir="$DATA_DIR" sendrawtransaction "$SIGNED_TX_CHILD")
if [ $? -ne 0 ]; then
    echo "Error: Falló la transmisión de la transacción child."
    exit 1
fi
echo "TXID de la transacción Child: $CHILD_TXID"

sleep 2 # Give time for the transaction to propagate in the mempool

# Realizar consulta getmempoolentry para la transacción child
echo -e "\n--- Detalles de la transacción Child en el mempool (antes de RBF) ---"
if bitcoin-cli -datadir="$DATA_DIR" getmempoolentry "$CHILD_TXID" > /dev/null 2>&1; then
    bitcoin-cli -datadir="$DATA_DIR" getmempoolentry "$CHILD_TXID" | jq .
else
    echo "La transacción Child (TXID: $CHILD_TXID) no se encontró en el mempool antes de RBF. Esto es inesperado."
fi

---
## PASO 6: AUMENTAR LA TARIFA DE LA TRANSACCIÓN PARENT USANDO RBF (Manual)

print_header "PASO 6: AUMENTANDO LA TARIFA DE LA TRANSACCIÓN PARENT (RBF manual)"

# Aumentar la tarifa en 10,000 satoshis (0.0001 BTC)
INCREASE_FEE=0.0001
# Recalculate Miner's change amount. Miner's original change was 29.99999 BTC.
# The new change will be 29.99999 - 0.0001 = 29.99989 BTC.
NEW_MINER_CHANGE_AMOUNT=$(echo "$MINER_AMOUNT - $INCREASE_FEE" | bc)

echo "Creando una nueva transacción conflictiva (RBF) para la transacción parent..."
echo "Nueva cantidad de cambio para Miner: $NEW_MINER_CHANGE_AMOUNT BTC"

# Create the new conflicting parent transaction (with same inputs and RBF enabled by default from walletrbf=1)
# Use sequence number 1 or higher for RBF to be active (0 disables RBF)
RAW_TX_PARENT_RBF_HEX=$(bitcoin-cli -datadir="$DATA_DIR" createrawtransaction \
  "[{\"txid\": \"$INPUT_TXID_0\", \"vout\": $INPUT_VOUT_0, \"sequence\": 1}, {\"txid\": \"$INPUT_TXID_1\", \"vout\": $INPUT_VOUT_1, \"sequence\": 1}]" \
  "{\"${TRADER_RECEIVE_ADDRESS}\": 70, \"${MINER_CHANGE_ADDRESS}\": $NEW_MINER_CHANGE_AMOUNT}" \
)

if [ -z "$RAW_TX_PARENT_RBF_HEX" ]; then
    echo "Error: Falló la creación de la transacción raw parent RBF."
    exit 1
fi
echo "Transacción Parent RBF Raw (HEX): $RAW_TX_PARENT_RBF_HEX"

# Firmar la nueva transacción parent conflictiva
echo "Firmando la nueva transacción parent RBF..."
SIGNED_TX_PARENT_RBF=$(bitcoin-cli -datadir="$DATA_DIR" -rpcwallet=$MINER_WALLET signrawtransactionwithwallet "$RAW_TX_PARENT_RBF_HEX" | jq -r '.hex')

if [ -z "$SIGNED_TX_PARENT_RBF" ]; then
    echo "Error: Falló la firma de la transacción parent RBF."
    exit 1
fi

# Transmitir la nueva transacción parent conflictiva
echo "Transmitiendo la nueva transacción parent RBF..."
PARENT_RBF_TXID=$(bitcoin-cli -datadir="$DATA_DIR" sendrawtransaction "$SIGNED_TX_PARENT_RBF")
if [ $? -ne 0 ]; then
    echo "Error: Falló la transmisión de la transacción parent RBF. Asegúrate de que la tarifa sea suficiente para reemplazar la anterior."
    exit 1
fi
echo "Nuevo TXID de la transacción Parent (RBF): $PARENT_RBF_TXID"

sleep 2 # Give time for the RBF transaction to replace the original in the mempool

---
## PASO 7: CONSULTA AL MEMPOOL DE LA TRANSACCIÓN CHILD (después de RBF)

print_header "PASO 7: CONSULTANDO LA TRANSACCIÓN CHILD EN EL MEMPOOL (DESPUÉS DE RBF)"

echo -e "\n--- Detalles de la transacción Child en el mempool (después de RBF) ---"
# It's possible the child transaction is no longer in the mempool if it's orphaned.
# We'll still try to query it.
if bitcoin-cli -datadir="$DATA_DIR" getmempoolentry "$CHILD_TXID" > /dev/null 2>&1; then
    bitcoin-cli -datadir="$DATA_DIR" getmempoolentry "$CHILD_TXID" | jq .
else
    echo "La transacción Child (TXID: $CHILD_TXID) ya no se encuentra en el mempool."
    echo "(Esto es esperado, ya que su transacción padre fue reemplazada)."
fi

---
## PASO 8: EXPLICACIÓN DE LOS CAMBIOS EN EL MEMPOOL DE LA TRANSACCIÓN CHILD

print_header "PASO 8: EXPLICACIÓN DE LOS CAMBIOS EN EL MEMPOOL DE LA TRANSACCIÓN CHILD"

echo "Explicación:"
echo "---------------------------------------------------------------------------------------------------"
echo "Cuando la primera **transacción Parent** (TXID: ${PARENT_TXID}) fue transmitida y entró en el mempool,"
echo "la **transacción Child** (TXID: ${CHILD_TXID}) se creó inmediatamente después, gastando una de sus"
echo "salidas (el cambio para Miner). Esto estableció una relación 'parent-child' en el mempool."
echo ""
echo "En la primera consulta de 'getmempoolentry' para la transacción Child, es posible que hayas visto"
echo "que la transacción Parent original (${PARENT_TXID}) figuraba en el campo 'depends' (o similar)."
echo "Esto significa que la transacción Child dependía de la confirmación de la transacción Parent."
echo ""
echo "Cuando se transmitió la **nueva transacción Parent con RBF habilitado** (TXID: ${PARENT_RBF_TXID}),"
echo "esta nueva transacción tenía las *mismas entradas* que la transacción Parent original pero una *tarifa más alta*."
echo "Los nodos de Bitcoin que soportan RBF reconocieron esto como un reemplazo válido."
echo ""
echo "El nodo, al procesar la transacción RBF, **reemplazó la transacción Parent original en su mempool**"
echo "con la nueva transacción Parent con la tarifa aumentada. Debido a esta sustitución, la"
echo "**transacción Child quedó huérfana (orphan)**."
echo ""
echo "En la segunda consulta de 'getmempoolentry' para la transacción Child, es probable que no la veas"
echo "más en el mempool del nodo o que su estado haya cambiado para indicar que sus padres no están disponibles."
echo "Esto se debe a que la entrada que gastaba (la salida de cambio de la transacción Parent original) ya no existe"
echo "en el mempool porque la transacción Parent original fue reemplazada. La transacción Child ahora"
echo "hace referencia a una transacción que no está en el mempool ni ha sido confirmada en un bloque."
echo ""
echo "Para que la transacción Child vuelva a ser válida y se propague, necesitaría ser recreada"
echo "gastando la salida de cambio de la *nueva* transacción Parent (la RBF), o esperar a que la"
echo "nueva transacción Parent sea confirmada en un bloque para que su salida de cambio esté disponible."
echo "---------------------------------------------------------------------------------------------------"

print_header "SCRIPT FINALIZADO"
exit 0
