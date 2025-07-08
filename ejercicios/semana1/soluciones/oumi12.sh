BITCOIN_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

echo "--- Configuración ---"

echo "1. Descargando binarios de Bitcoin Core..."
wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS

echo "2. Verificando binarios..."
if grep bitcoin-29.0-x86_64-linux-gnu.tar.gz SHA256SUMS | sha256sum -c -; then
    echo "Binary signature verification successful"
else
    echo "Error: Verificación fallida"
    exit 1
fi

echo "3. Extrayendo e instalando binarios..."
tar -xzf bitcoin-29.0-x86_64-linux-gnu.tar.gz
sudo cp bitcoin-29.0/bin/* /usr/local/bin/
echo "Binarios instalados en /usr/local/bin/"

echo -e "\n--- Inicio ---"

echo "1. Creando directorio de datos y bitcoin.conf..."
mkdir -p "$BITCOIN_DATA_DIR"
cat << EOF > "$BITCOIN_DATA_DIR/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

echo "2. Iniciando bitcoind..."
bitcoind -daemon -datadir="$BITCOIN_DATA_DIR"
sleep 5

echo "3. Creando billeteras '$MINER_WALLET' y '$TRADER_WALLET'..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MINER_WALLET"
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$TRADER_WALLET"

echo "4. Generando dirección del Miner..."
MINER_ADDRESS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress "Mining Reward")
echo "Dirección del Miner: $MINER_ADDRESS"

echo "5. Minando bloques..."
NUM_BLOCKS=101
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress "$NUM_BLOCKS" "$MINER_ADDRESS"

echo "Se necesitaron $NUM_BLOCKS bloques para obtener un saldo positivo."


MINER_BALANCE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)
echo "Saldo de '$MINER_WALLET': $MINER_BALANCE BTC"

echo -e "\n--- Uso ---"

echo "1. Creando dirección receptora del Trader..."
TRADER_ADDRESS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getnewaddress "Received")
echo "Dirección del Trader: $TRADER_ADDRESS"

echo "2. Enviando 20 BTC del Miner al Trader..."
TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$TRADER_ADDRESS" 20)
echo "TXID: $TXID"

echo "3. Obteniendo transacción no confirmada del mempool..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$TXID"

echo "4. Confirmando transacción con 1 bloque adicional..."
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 1 "$MINER_ADDRESS"

echo -e "\n--- Detalles de la Transacción ---"

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

echo "txid: $TXID"
echo "<De, Cantidad>: $MINER_ADDRESS, $INPUT_AMOUNT BTC (total debitado)"
echo "<Enviar, Cantidad>: $TRADER_ADDRESS, $SEND_AMOUNT BTC"
echo "<Cambio, Cantidad>: $MINER_ADDRESS, $CHANGE_AMOUNT BTC"
echo "Comisiones: $FEES BTC"
echo "Bloque: $BLOCK_HEIGHT"

MINER_BALANCE_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)
TRADER_BALANCE_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getbalance)

echo "Miner Balance: $MINER_BALANCE_FINAL BTC"
echo "Trader Balance: $TRADER_BALANCE_FINAL BTC"

echo -e "\n--- Limpieza ---"
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop
sleep 3
echo "bitcoind detenido."
