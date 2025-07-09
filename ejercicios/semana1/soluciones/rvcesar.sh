#!/bin/bash

# ==============================================================================
# Script para la configuración y uso de Bitcoin Core en modo RegTest
# Creado por: rvcesar
# ==============================================================================

# --- Variables de Configuración ---
BITCOIN_VERSION="29.0" # Puedes cambiar esto a la última versión si es necesario
ARCH="x86_64-linux-gnu"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz"
CHECKSUM_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
SIGNATURE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc"
DATA_DIR="$HOME/.bitcoin"
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
  # -datadir apunta al directorio de datos para asegurar que detenemos el demonio correcto
  if bitcoin-cli -datadir="$DATA_DIR" ping > /dev/null 2>&1; then
    echo "Deteniendo bitcoind..."
    bitcoin-cli -datadir="$DATA_DIR" stop
    echo "bitcoind detenido."
  else
    echo "bitcoind no parece estar en ejecución."
  fi
}

# Atrapa la salida del script para ejecutar la limpieza
trap cleanup EXIT

# --- Inicio del Script ---

# 1. Verificación de Dependencias
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

# ==============================================================================
# == PASO 1: CONFIGURACIÓN                                                    ==
# ==============================================================================
print_header "PASO 1: DESCARGA Y VERIFICACIÓN DE BITCOIN CORE"

# Descarga de binarios, hashes y firmas
echo "Descargando Bitcoin Core v${BITCOIN_VERSION}..."
wget -q --show-progress -O bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz "$BITCOIN_URL"
echo "Descargando archivos de suma de verificación (checksums)..."
wget -q -O SHA256SUMS "$CHECKSUM_URL"
echo "Descargando firmas..."
wget -q -O SHA256SUMS.asc "$SIGNATURE_URL"

# Verificación de la integridad del archivo
echo -e "\nVerificando la suma de verificación (checksum) del archivo descargado..."
# El siguiente comando busca el hash del archivo tar.gz dentro del archivo SHA256SUMS y lo verifica
sha256sum --ignore-missing -c SHA256SUMS 2>/dev/null | grep "bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz: OK"
if [ $? -ne 0 ]; then
  echo "Error: La verificación de la suma de verificación falló. El archivo puede estar corrupto."
  exit 1
fi
echo "Suma de verificación correcta."

# Verificación de la firma GPG
echo -e "\nImportando las claves de firma de los desarrolladores de Bitcoin Core..."
# Clonar el repositorio guix.sigs para obtener las claves más recientes
if [ -d "guix.sigs" ]; then
    echo "Directorio 'guix.sigs' ya existe, actualizando..."
    (cd guix.sigs && git pull)
else
    echo "Clonando repositorio 'guix.sigs'..."
    git clone https://github.com/bitcoin-core/guix.sigs
fi

# Importar todas las claves de los constructores
gpg --import guix.sigs/builder-keys/* 2>/dev/null

echo -e "\nVerificando la firma GPG del archivo de sumas de verificación..."
# El "2>&1" se asegura de que tanto la salida normal como los errores/warnings sean revisados por grep.
if gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -q "Good signature"; then
  echo -e "\n\e[32mVerificación exitosa de la firma binaria.\e[0m" # Mensaje en verde
else
  echo "Error: La firma GPG no es válida o no se pudo verificar. ¡El archivo de sumas de verificación podría haber sido manipulado!"
  echo "Asegúrate de que las claves GPG de los desarrolladores estén actualizadas."
  exit 1
fi

# Extracción y configuración del PATH
echo -e "\nExtrayendo los binarios..."
tar -xzf bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz
# Añade el directorio bin al PATH para esta sesión de script
export PATH="$PWD/bitcoin-${BITCOIN_VERSION}/bin:$PATH"
echo "PATH actualizado para la sesión actual."

# ==============================================================================
# == PASO 2: INICIO Y CONFIGURACIÓN DEL NODO                                  ==
# ==============================================================================
print_header "PASO 2: INICIO DEL NODO Y CREACIÓN DE BILLETERAS"

# Crear directorio .bitcoin y archivo de configuración
echo "Creando el directorio de datos en $DATA_DIR..."
mkdir -p "$DATA_DIR"

echo "Creando el archivo de configuración bitcoin.conf..."
cat > "$CONF_FILE" << EOF
# Configuraciones para modo RegTest
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

# Iniciar bitcoind
echo "Iniciando bitcoind en modo demonio..."
bitcoind -daemon
# Esperar un poco para que el servidor se inicie completamente
sleep 5

echo "Verificando que bitcoind esté en ejecución..."
bitcoin-cli ping
if [ $? -ne 0 ]; then
    echo "Error: No se pudo conectar con bitcoind. Revisar los logs en $DATA_DIR/regtest/debug.log"
    exit 1
fi

# Crear las billeteras
echo "Creando billetera 'Miner'..."
bitcoin-cli createwallet "$MINER_WALLET" > /dev/null

echo "Creando billetera 'Trader'..."
bitcoin-cli createwallet "$TRADER_WALLET" > /dev/null

# Generar dirección de minería
echo "Generando nueva dirección para la billetera 'Miner'..."
MINER_ADDRESS=$(bitcoin-cli -rpcwallet=$MINER_WALLET getnewaddress "Recompensa de Mineria")
echo "Dirección de minería: $MINER_ADDRESS"

# Minar bloques
echo "Minando bloques para obtener un saldo positivo..."
# Los fondos de coinbase (recompensas de bloque) requieren 100 confirmaciones para poder ser gastados.
# Por lo tanto, necesitamos minar 100 bloques para que la recompensa del primer bloque madure.
# Al minar 101 bloques, la recompensa del bloque #1 se vuelve gastable.
BLOCKS_TO_MATURE=101
bitcoin-cli -rpcwallet=$MINER_WALLET generatetoaddress $BLOCKS_TO_MATURE "$MINER_ADDRESS" > /dev/null

echo ""
echo "¿Cuántos bloques se necesitaron para obtener un saldo positivo?"
echo "Respuesta: Se necesitaron $BLOCKS_TO_MATURE bloques."
echo ""
echo "Breve comentario sobre el comportamiento del saldo:"
echo "----------------------------------------------------"
echo "Las recompensas por minar un bloque (transacciones de 'coinbase') no se pueden gastar inmediatamente. Deben 'madurar' durante 100 bloques. Esto es una regla del protocolo Bitcoin para prevenir que reorganizaciones de la cadena de bloques (reorgs) huérfanas invaliden las recompensas recién creadas. Por lo tanto, para que el saldo de la primera recompensa de bloque (bloque #1) esté disponible, debemos minar 100 bloques adicionales sobre él, llegando a una altura de bloque de 101."
echo "----------------------------------------------------"
echo ""

# Imprimir saldo de la billetera Miner
MINER_BALANCE=$(bitcoin-cli -rpcwallet=$MINER_WALLET getbalance)
echo -e "Saldo inicial de la billetera '$MINER_WALLET': \e[33m$MINER_BALANCE BTC\e[0m"

# ==============================================================================
# == PASO 3: USO Y TRANSACCIONES                                              ==
# ==============================================================================
print_header "PASO 3: CREANDO Y VERIFICANDO UNA TRANSACCIÓN"

# Crear dirección de recepción en la billetera Trader
echo "Creando dirección de recepción en la billetera 'Trader'..."
TRADER_ADDRESS=$(bitcoin-cli -rpcwallet=$TRADER_WALLET getnewaddress "Recibido")
echo "Dirección de recepción del Trader: $TRADER_ADDRESS"

# Enviar transacción
echo -e "\nEnviando 20 BTC desde '$MINER_WALLET' a '$TRADER_WALLET'..."
TXID=$(bitcoin-cli -rpcwallet=$MINER_WALLET sendtoaddress "$TRADER_ADDRESS" 20)
echo "ID de la transacción (TXID): $TXID"

# Obtener transacción no confirmada desde la mempool
echo -e "\nObteniendo la transacción desde la mempool..."
MEMPOOL_ENTRY=$(bitcoin-cli getmempoolentry "$TXID")
echo "$MEMPOOL_ENTRY" | jq

# Confirmar la transacción minando un bloque adicional
echo -e "\nConfirmando la transacción minando 1 bloque adicional..."
bitcoin-cli -rpcwallet=$MINER_WALLET generatetoaddress 1 "$MINER_ADDRESS" > /dev/null
echo "Transacción confirmada."

# Obtener y mostrar los detalles de la transacción
echo -e "\n--- DETALLES DE LA TRANSACCIÓN CONFIRMADA ---"

# Usamos gettransaction para obtener los detalles desde la perspectiva de la billetera
TX_DETAILS=$(bitcoin-cli -rpcwallet=$MINER_WALLET gettransaction "$TXID")

# Usamos getrawtransaction para un análisis más profundo de las entradas y salidas
RAW_TX_HEX=$(bitcoin-cli getrawtransaction "$TXID")
DECODED_TX=$(bitcoin-cli decoderawtransaction "$RAW_TX_HEX")

# Extraer información
FEE=$(echo "$TX_DETAILS" | jq -r '.fee')
BLOCK_HEIGHT=$(echo "$TX_DETAILS" | jq -r '.blockheight')
INPUT_TXID=$(echo "$DECODED_TX" | jq -r '.vin[0].txid')
INPUT_VOUT=$(echo "$DECODED_TX" | jq -r '.vin[0].vout')
RAW_INPUT_TX=$(bitcoin-cli getrawtransaction "$INPUT_TXID" true)
INPUT_ADDRESS=$(echo "$RAW_INPUT_TX" | jq -r ".vout[$INPUT_VOUT].scriptPubKey.address")
INPUT_AMOUNT=$(echo "$RAW_INPUT_TX" | jq -r ".vout[$INPUT_VOUT].value")

SENT_AMOUNT=$(echo "$DECODED_TX" | jq -r ".vout[] | select(.scriptPubKey.address==\"$TRADER_ADDRESS\") | .value")
CHANGE_OUTPUT=$(echo "$DECODED_TX" | jq -r ".vout[] | select(.scriptPubKey.address!=\"$TRADER_ADDRESS\")")
CHANGE_ADDRESS=$(echo "$CHANGE_OUTPUT" | jq -r '.scriptPubKey.address')
CHANGE_AMOUNT=$(echo "$CHANGE_OUTPUT" | jq -r '.value')

FINAL_MINER_BALANCE=$(bitcoin-cli -rpcwallet=$MINER_WALLET getbalance)
FINAL_TRADER_BALANCE=$(bitcoin-cli -rpcwallet=$TRADER_WALLET getbalance)

# Mostrar resultados formateados
echo "txid:          $TXID"
echo "<De, Cantidad>:    $INPUT_ADDRESS, $INPUT_AMOUNT BTC"
echo "<Enviar, Cantidad> $TRADER_ADDRESS, $SENT_AMOUNT BTC"
echo "<Cambio, Cantidad> $CHANGE_ADDRESS, $CHANGE_AMOUNT BTC"
# La comisión se muestra como un número negativo, usamos sed para quitar el signo
echo "Comisiones:      $(echo "$FEE" | sed 's/-//') BTC"
echo "Bloque:          $BLOCK_HEIGHT"
echo -e "Saldo de Miner:  \e[33m$FINAL_MINER_BALANCE BTC\e[0m"
echo -e "Saldo de Trader: \e[33m$FINAL_TRADER_BALANCE BTC\e[0m"

print_header "SCRIPT FINALIZADO"
# La función cleanup se llamará automáticamente al salir.
exit 0
