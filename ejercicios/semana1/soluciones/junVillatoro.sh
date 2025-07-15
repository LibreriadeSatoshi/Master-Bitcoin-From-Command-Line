#!/bin/bash

BTC_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

echo "-Configurando el entorno-"
#Descargando e Instalando binarios
wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS

if sha256sum -c --ignore-missing SHA256SUMS | grep "bitcoin-29.0-x86_64-linux-gnu.tar.gz: OK" > /dev/null; 
then echo "Binarios verificados correctamente"
else echo "La verificación de los binarios falló"
exit 1
fi

tar -xzf bitcoin-29.0-x86_64-linux-gnu.tar.gz
sudo cp bitcoin-29.0/bin/* /usr/local/bin/

echo "-Inicio Ejercicio-"

echo "Paso 1. Creación del directorio y archivo de configuración"
mkdir -p "$BTC_DATA_DIR"
cat <<EOF > "$BTC_DATA_DIR/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

#Iniciando el daemon
echo "Paso 2. Iniciando Bitcoind"
bitcoind -daemon -datadir="$BTC_DATA_DIR"
sleep 5
bitcoin-cli getblockchaininfo >/dev/null || {
    echo "El inicio del daemon falló"
    exit 1
}
echo "El inicio del daemon fue exitoso"

#Creando las billeteras
echo "Paso 3. Creación de las billeteras"
bitcoin-cli -datadir="$BTC_DATA_DIR" createwallet "$MINER_WALLET"
bitcoin-cli -datadir="$BTC_DATA_DIR" createwallet "$TRADER_WALLET"

#Generar dirección
echo "Paso 4. Generación de la dirección de Miner"
MINER_WALLET_ADDRESS=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress "Recompensa de mineria" )
echo "La dirección del Miner es: $MINER_WALLET_ADDRESS"

#Extrasión de bloques
echo "Paso 5. Extraer bloques a esta dirección"
BLOCKS=101
bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" generatetoaddress "$BLOCKS" "$MINER_WALLET_ADDRESS"

echo "Se necesitan $BLOCKS bloques para obtener un saldo positivo en la billetera"

MINER_WALLET_BALANCE=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)

#Imprimir el saldo de MINER
echo "El saldo actual de $MINER_WALLET es: $MINER_WALLET_BALANCE BTC"

echo "-Uso-"

echo "Punto 1. Creación de dirección receptora de Trader"
TRADER_WALLET_ADDRESS=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$TRADER_WALLET" getnewaddress "Recibido" )
echo "Dirección generada: $TRADER_WALLET_ADDRESS"

echo "Punto 2. Enviando 20 BTC entre wallets"
TXID=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$TRADER_WALLET_ADDRESS" 20)

echo "Punto 3. Obtener la transacción no confirmada del mempool"
bitcoin-cli -datadir="$BTC_DATA_DIR" getmempoolentry "$TXID"

echo "Punto 4. Confirmar la transacción creando 1 bloque adicional"
bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" generatetoaddress 1 "$MINER_WALLET_ADDRESS"

echo "Punto 5. Obtener los datos de la transacción"
MINER_WALLET_TX_DETAILS=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" gettransaction "$TXID")
TRADER_WALLET_TX_DETAILS=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$TRADER_WALLET" gettransaction "$TXID")
RAW_TX_DETAILS=$(bitcoin-cli -datadir="$BTC_DATA_DIR" gettransaction "$TXID" true)

INPUT_TX_AMOUNT=$(echo "$MINER_WALLET_TX_DETAILS" | jq -r '.amount | abs')
SEND_TX_AMOUNT=$(echo "$TRADER_WALLET_TX_DETAILS" | jq -r '.amount | abs')
CHANGE_TX_AMOUNT=$(echo "$RAW_TX_DETAILS" | jq -r --arg trader_addre "$TRADER_WALLET_ADDRESS" '.vout[] | select(.scriptPubKey.address != $trader_addre) | .value' | head -1)
if [ -z "$CHANGE_TX_AMOUNT" ] || [ "$CHANGE_TX_AMOUNT" === "null" ]; then
CHANGE_TX_AMOUNT="0.0"
fi
FEES_TX=$(echo "$MINER_WALLET_TX_DETAILS" | jq -r '.fee | abs // 0')
BLOCK_HEIGHT=$(echo "$MINER_WALLET_TX_DETAILS" | jq -r '.blockheight // "N/A"')

echo "Detalles de la transacción:"

echo "txid: $TXID"
echo "<De, Cantidad>: $MINER_WALLET_ADDRESS, $INPUT_TX_AMOUNT BTC"
echo "<Enviar, Cantidad>: $TRADER_WALLET_ADDRESS, $SEND_TX_AMOUNT BTC"
echo "<Cambio, Cantidad>: $MINER_WALLET_ADDRESS, $CHANGE_TX_AMOUNT BTC"
echo "Comisiones: $FEES_TX BTC"
echo "Bloque: $BLOCK_HEIGHT"

MINER_WALLET_BALANCE=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$MINER_WALLET" getbalance)
TRADER_WALLET_BALANCE=$(bitcoin-cli -datadir="$BTC_DATA_DIR" -rpcwallet="$TRADER_WALLET" getbalance)

echo "Saldo de Miner: $MINER_WALLET_BALANCE"
echo "Saldo de Trader: $TRADER_WALLET_BALANCE"

echo "Finalización"
bitcoin-cli -datadir="$BTC_DATA_DIR" stop
sleep 3
echo "bitcoind se ha detenido."