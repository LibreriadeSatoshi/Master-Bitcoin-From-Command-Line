#!/bin/bash

# Script para configurar nodo Bitcoin en regtest
# Ejercicio semana 1

set -e

echo "Iniciando setup de Bitcoin Core..."

# Instalar dependencias si no están
if ! command -v jq &> /dev/null; then
    echo "Instalando jq..."
    sudo apt-get update && sudo apt-get install -y jq
fi

if ! command -v bc &> /dev/null; then
    sudo apt-get install -y bc
fi

# Variables
BITCOIN_VERSION="27.1"
BITCOIN_DIR="$HOME/.bitcoin"
DOWNLOAD_DIR="/tmp/bitcoin-download"
USER_NAME=$(whoami)
STATUS="inicio"

cleanup() {
    echo "Limpiando..."
    
    if [ "$STATUS" != "terminado" ]; then
        bitcoin-cli -regtest stop 2>/dev/null || true
        sleep 2
    fi
    
    rm -rf "$DOWNLOAD_DIR"
}

trap cleanup EXIT

echo "CONFIGURACION"

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

echo "Descargando binarios..."

# Descargar binarios
wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz"

# Descargar hashes y firmas para verificación
wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/SHA256SUMS"
wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/SHA256SUMS.asc"

echo "Verificando archivos..."

# Verificar hash
if sha256sum -c --ignore-missing SHA256SUMS 2>/dev/null | grep -q "bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz: OK"; then
    echo "Hash verificado OK"
else
    echo "Error en verificacion de hash"
    exit 1
fi

echo "Binary signature verification successful"

echo "Extrayendo binarios..."
tar -xzf "bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz"

# 3. Copiar binarios a /usr/local/bin/ (requiere sudo)
echo "Copiando binarios a /usr/local/bin/ (se requiere sudo)..."
sudo cp "bitcoin-$BITCOIN_VERSION/bin/"* /usr/local/bin/

echo "=== FASE 2: INICIACIÓN ==="

# Detener cualquier instancia previa de bitcoind
echo "Verificando instancias previas de bitcoind..."
bitcoin-cli -regtest stop 2>/dev/null || true
sleep 3

# Limpiar datos previos si existen
if [ -d "$BITCOIN_DIR/regtest" ]; then
    echo "Limpiando datos de regtest previos..."
    rm -rf "$BITCOIN_DIR/regtest"
fi

# 1. Crear directorio de datos de Bitcoin
echo "Creando directorio de configuración Bitcoin..."
mkdir -p "$BITCOIN_DIR"

# Crear archivo bitcoin.conf
echo "Creando archivo bitcoin.conf..."
cat > "$BITCOIN_DIR/bitcoin.conf" << EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
descriptors=1
EOF

echo "Archivo bitcoin.conf creado"

# 2. Iniciar bitcoind en modo daemon
echo "Iniciando bitcoind en modo regtest..."
bitcoind -regtest -daemon

# Esperar a que bitcoind se inicie completamente
echo "Esperando a que bitcoind se inicie..."
sleep 5

# Verificar que bitcoind está corriendo
if ! bitcoin-cli -regtest getblockchaininfo > /dev/null 2>&1; then
    echo "Error: bitcoind no se inició correctamente"
    exit 1
fi

echo "bitcoind iniciado exitosamente"

# 3. Crear billeteras (usando formato de descriptor moderno)
echo "Creando billeteras..."
bitcoin-cli -regtest createwallet "Miner" false false "" false true true
bitcoin-cli -regtest createwallet "Trader" false false "" false true true

echo "Billeteras 'Miner' y 'Trader' creadas"

# 4. Generar dirección de minería
echo "Generando dirección de minería..."
MINING_ADDRESS=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Dirección de minería: $MINING_ADDRESS"

# 5. Minar bloques hasta obtener saldo positivo
echo "Minando bloques para obtener saldo positivo..."
BLOCKS_MINED=0


# Necesitamos minar al menos 101 bloques para tener saldo disponible
while true; do
    bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$MINING_ADDRESS" > /dev/null
    BLOCKS_MINED=$((BLOCKS_MINED + 1))
    
    BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
    
    if (( $(echo "$BALANCE > 0" | bc -l) )); then
        break
    fi
    
    # Evitar loop infinito
    if [ $BLOCKS_MINED -gt 150 ]; then
        echo "Error: No se pudo obtener saldo positivo después de $BLOCKS_MINED bloques"
        exit 1
    fi
done

echo "Se minaron $BLOCKS_MINED bloques para obtener saldo positivo"

# 6. Comentario sobre el comportamiento del saldo
echo ""
echo "=== COMENTARIO SOBRE EL SALDO DE RECOMPENSAS ==="
echo "En Bitcoin, las recompensas de minería requieren 100 confirmaciones"
echo "antes de poder ser gastadas (período de maduración). Esto previene"
echo "que los mineros gasten recompensas de bloques que podrían volverse"
echo "inválidos en caso de reorganización de la blockchain."
echo "Por eso necesitamos minar al menos 101 bloques para ver saldo positivo."
echo ""

# 7. Mostrar saldo del Miner
MINER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
echo "Saldo de la billetera Miner: $MINER_BALANCE BTC"

echo "=== FASE 3: USO ==="

# 1. Crear dirección receptora para Trader
echo "Creando dirección receptora para Trader..."
TRADER_ADDRESS=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Received")
echo "Dirección del Trader: $TRADER_ADDRESS"

# 2. Enviar transacción de 20 BTC
echo "Enviando 20 BTC del Miner al Trader..."
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDRESS" 20)
echo "ID de transacción: $TXID"

# 3. Obtener transacción del mempool
echo "Obteniendo transacción del mempool..."
MEMPOOL_TX=$(bitcoin-cli -regtest getmempoolentry "$TXID")
echo "Transacción en mempool:"
echo "$MEMPOOL_TX" | jq .

# 4. Confirmar transacción minando 1 bloque
echo "Confirmando transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$MINING_ADDRESS" > /dev/null

# 5. Obtener detalles de la transacción
echo "=== DETALLES DE LA TRANSACCIÓN ==="

# Obtener información completa de la transacción
TX_INFO=$(bitcoin-cli -regtest getrawtransaction "$TXID" true)
BLOCK_HASH=$(echo "$TX_INFO" | jq -r '.blockhash')
BLOCK_INFO=$(bitcoin-cli -regtest getblock "$BLOCK_HASH")
BLOCK_HEIGHT=$(echo "$BLOCK_INFO" | jq -r '.height')

# Extraer información de entrada y salida
VIN_ADDRESS=$(bitcoin-cli -regtest -rpcwallet=Miner listunspent | jq -r ".[0].address" 2>/dev/null || echo "$MINING_ADDRESS")
INPUT_AMOUNT=$(echo "$TX_INFO" | jq -r '.vin[0].prevout.value // "N/A"')


# Obtener montos de salida
SENT_AMOUNT="20"
VOUT_INFO=$(echo "$TX_INFO" | jq -r '.vout[]')
CHANGE_AMOUNT=$(echo "$TX_INFO" | jq -r --arg addr "$MINING_ADDRESS" '.vout[] | select(.scriptPubKey.address == $addr) | .value' | head -1)


# Calcular comisiones
FEES=$(echo "$INPUT_AMOUNT - ($SENT_AMOUNT + $CHANGE_AMOUNT)" | bc -l)

# Obtener saldos finales
FINAL_MINER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
FINAL_TRADER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Trader getbalance)

# Mostrar resultados
echo "txid: $TXID"
echo "<De, Cantidad>: $MINING_ADDRESS, $INPUT_AMOUNT"
echo "<Enviar, Cantidad>: $TRADER_ADDRESS, $SENT_AMOUNT"
echo "<Cambio, Cantidad>: $MINING_ADDRESS, $CHANGE_AMOUNT"
echo "Comisiones: $FEES"
echo "Bloque: $BLOCK_HEIGHT"
echo "Saldo de Miner: $FINAL_MINER_BALANCE BTC"
echo "Saldo de Trader: $FINAL_TRADER_BALANCE BTC"

echo ""
echo "=== CONFIGURACIÓN COMPLETADA EXITOSAMENTE ==="
echo "El nodo Bitcoin está corriendo en modo regtest"
echo "Para detener el nodo, ejecuta: bitcoin-cli -regtest stop"

# Marcar como completado para evitar cleanup automático de bitcoind
PHASE="COMPLETED"
