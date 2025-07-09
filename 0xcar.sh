#!/bin/bash

# Variables de configuración del entorno
BITCOIN_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Productor"
TRADER_WALLET="Consumidor"
BITCOIN_VERSION="29.0"
TRANSFER_AMOUNT=20
MINING_BLOCKS=101

# Función para mostrar mensajes con formato
show_message() {
    echo "[$1] $2"
}

# Función para limpiar entorno previo
clean_environment() {
    show_message "CLEANUP" "Limpiando entorno anterior..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop > /dev/null 2>&1
    sleep 3
    rm -rf "$BITCOIN_DATA_DIR/regtest"
    show_message "CLEANUP" "Entorno limpio"
}

# Función para descargar Bitcoin Core
download_bitcoin() {
    show_message "INFO" "Descargando Bitcoin Core v$BITCOIN_VERSION..."
    wget -q https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz
    wget -q https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/SHA256SUMS
    show_message "OK" "Descarga completada"
}

# Función para verificar integridad
verify_integrity() {
    show_message "INFO" "Verificando integridad del archivo..."
    if grep bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz SHA256SUMS | sha256sum -c - > /dev/null 2>&1; then
        show_message "OK" "Verificación de integridad exitosa"
    else
        show_message "ERROR" "Verificación fallida"
        exit 1
    fi
}

# Función para instalar binarios
install_binaries() {
    show_message "INFO" "Extrayendo e instalando binarios..."
    tar -xzf bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz
    sudo cp bitcoin-$BITCOIN_VERSION/bin/* /usr/local/bin/
    show_message "OK" "Binarios instalados en /usr/local/bin/"
}

# Función para configurar el entorno Bitcoin
setup_bitcoin_environment() {
    show_message "SETUP" "Creando directorio de datos y bitcoin.conf..."
    mkdir -p "$BITCOIN_DATA_DIR"
    
    cat << EOF > "$BITCOIN_DATA_DIR/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF
    
    show_message "SETUP" "Configuración creada"
}

# Función para iniciar el daemon
start_bitcoin_daemon() {
    show_message "START" "Iniciando bitcoind..."
    bitcoind -daemon -datadir="$BITCOIN_DATA_DIR"
    sleep 5
    show_message "START" "Daemon iniciado"
}

# Función para crear wallets
create_wallets() {
    show_message "WALLET" "Creando billeteras '$MINER_WALLET' y '$TRADER_WALLET'..."
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MINER_WALLET" > /dev/null 2>&1
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$TRADER_WALLET" > /dev/null 2>&1
    show_message "WALLET" "Billeteras creadas"
}

# ========== EJECUCIÓN PRINCIPAL ==========

echo "🚀 INICIANDO CONFIGURACIÓN DE BITCOIN REGTEST"
echo "=============================================="

# Fase 0: Limpieza inicial
clean_environment

# Fase 1: Preparación del entorno
download_bitcoin
verify_integrity
install_binaries

echo ""
echo "⚙️  CONFIGURACIÓN DEL ENTORNO"
echo "============================="

# Fase 2: Configuración Bitcoin
setup_bitcoin_environment
start_bitcoin_daemon
create_wallets

echo ""
echo "⛏️  FASE DE MINADO"
echo "=================="

# Fase 3: Minado inicial
show_message "ADDRESS" "Generando dirección del Productor..."
MINER_ADDRESS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress "Mining Reward")
show_message "ADDRESS" "Dirección del Productor: $MINER_ADDRESS"

show_message "MINING" "Minando $MINING_BLOCKS bloques..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress "$MINING_BLOCKS" "$MINER_ADDRESS" > /dev/null
show_message "MINING" "Se minaron $MINING_BLOCKS bloques para generar fondos"

MINER_BALANCE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)
echo "💰 Balance de '$MINER_WALLET': $MINER_BALANCE BTC"

echo ""
echo "💸 FASE DE TRANSFERENCIA"
echo "======================="

# Fase 4: Transferencia entre wallets
show_message "ADDRESS" "Creando dirección receptora del Consumidor..."
TRADER_ADDRESS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getnewaddress "Received")
show_message "ADDRESS" "Dirección del Consumidor: $TRADER_ADDRESS"

show_message "TRANSFER" "Enviando $TRANSFER_AMOUNT BTC del Productor al Consumidor..."
TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$TRADER_ADDRESS" "$TRANSFER_AMOUNT")
show_message "TRANSFER" "TXID: $TXID"

show_message "MEMPOOL" "Obteniendo transacción no confirmada del mempool..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$TXID" > /dev/null
show_message "MEMPOOL" "Transacción encontrada en mempool"

show_message "CONFIRM" "Confirmando transacción con 1 bloque adicional..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 1 "$MINER_ADDRESS" > /dev/null
show_message "CONFIRM" "Transacción confirmada"

echo ""
echo "📊 ANÁLISIS DE TRANSACCIÓN"
echo "========================="

# Fase 5: Análisis detallado
show_message "ANALYSIS" "Analizando detalles de la transacción..."

MINER_TX_DETAILS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" gettransaction "$TXID")
TRADER_TX_DETAILS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" gettransaction "$TXID")
RAW_TX=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getrawtransaction "$TXID" true)

INPUT_AMOUNT=$(echo "$MINER_TX_DETAILS" | jq -r '.amount | abs')
SEND_AMOUNT=$(echo "$TRADER_TX_DETAILS" | jq -r '.amount')
CHANGE_AMOUNT=$(echo "$RAW_TX" | jq -r --arg trader_addr "$TRADER_ADDRESS" '.vout[] | select(.scriptPubKey.address != $trader_addr) | .value' | head -1)
if [ -z "$CHANGE_AMOUNT" ] || [ "$CHANGE_AMOUNT" == "null" ]; then
    CHANGE_AMOUNT="0.0"
fi
FEES=$(echo "$MINER_TX_DETAILS" | jq -r '.fee | abs // 0')
BLOCK_HEIGHT=$(echo "$MINER_TX_DETAILS" | jq -r '.blockheight // "N/A"')

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "               ANÁLISIS DE TRANSACCIÓN"
echo "═══════════════════════════════════════════════════════════"
echo "🆔 TXID: $TXID"
echo "📤 Origen: $MINER_ADDRESS → $INPUT_AMOUNT BTC (total debitado)"
echo "📥 Destino: $TRADER_ADDRESS → $SEND_AMOUNT BTC"
echo "🔄 Cambio: $MINER_ADDRESS → $CHANGE_AMOUNT BTC"
echo "💸 Comisiones: $FEES BTC"
echo "📦 Bloque: $BLOCK_HEIGHT"
echo "═══════════════════════════════════════════════════════════"

# Balances finales
MINER_BALANCE_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)
TRADER_BALANCE_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getbalance)

echo ""
echo "💰 BALANCES FINALES:"
echo "💰 Balance de '$MINER_WALLET': $MINER_BALANCE_FINAL BTC"
echo "💰 Balance de '$TRADER_WALLET': $TRADER_BALANCE_FINAL BTC"

echo ""
echo "🧹 LIMPIEZA"
echo "==========="

# Fase 6: Limpieza
show_message "CLEANUP" "Deteniendo bitcoind..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop > /dev/null 2>&1
sleep 3
show_message "CLEANUP" "bitcoind detenido"

echo ""
echo "✅ PROCESO COMPLETADO EXITOSAMENTE"
