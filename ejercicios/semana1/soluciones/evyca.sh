#!/bin/bash

# Configurar y operar un nodo Bitcoin en regtest
# Objetivo: Descargar, verificar, configurar y operar un nodo Bitcoin de prueba
# Autor: evyca
set -e

echo "Extraer  binarios desde bitcoin-29.0-x86_64-linux-gnu.tar.gz.2..."
tar -xzf bitcoin-29.0-x86_64-linux-gnu.tar.gz.2

#verificar si bitcoind ya esta instalado
if ! command -v bitcoind &> /dev/null; then
echo "Instalar  binarios en /usr/local/bin/..."
sudo cp bitcoin-29.0/bin/* /usr/local/bin/
else
    echo "bitcoind ya esta instalado"
fi  

#crear directorio de configuracion de bitcoin
BTC_CONF_DIR="$HOME/.bitcoin"
mkdir -p "$BTC_CONF_DIR"
cat > "$BTC_CONF_DIR/bitcoin.conf" <<EOF

# Configuración de Bitcoin en modo regtest
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

# verificar si bitcoind ya esta corriendo
if pgrep -x "bitcoind" > /dev/null; then
echo "⚠️ bitcoind ya está corriendo."
else
echo "Iniciando bitcoind en regtest..."
bitcoind -daemon -regtest
sleep 3
fi


echo "Cargando billeteras Miner y Trader..."

# Verificar si Miner existe
if ! bitcoin-cli -regtest -rpcwallet=Miner getwalletinfo &> /dev/null; then
  if [ -d "$HOME/.bitcoin/regtest/wallets/Miner" ]; then
    bitcoin-cli -regtest loadwallet "Miner"
  else
    bitcoin-cli -regtest createwallet "Miner"
  fi
fi

# Verificar si Trader existe
if ! bitcoin-cli -regtest -rpcwallet=Trader getwalletinfo &> /dev/null; then
  if [ -d "$HOME/.bitcoin/regtest/wallets/Trader" ]; then
    bitcoin-cli -regtest loadwallet "Trader"
  else
    bitcoin-cli -regtest createwallet "Trader"
  fi
fi

MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Recompensa de Mineria")

echo "Minar bloques para obtener saldo..."
BLOCKS_MINED=0
while true; do
    bitcoin-cli -regtest generatetoaddress 1 "$MINER_ADDR" > /dev/null
    BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
    ((BLOCKS_MINED++))
    [[ $(echo "$BALANCE > 0" | bc) -eq 1 ]] && break
done
echo "Se necesitaron $BLOCKS_MINED bloques para obtener saldo positivo."
echo "Comentario: Las recompensas de minería solo se pueden usar después de 100 bloques, por eso el saldo disponible toma tiempo."

echo "Saldo de Miner: $BALANCE BTC"

TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Recibido")
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)
echo "Transacción enviada. TXID: $TXID"

echo "Transacción no confirmada en mempool:"
bitcoin-cli -regtest getmempoolentry "$TXID"

bitcoin-cli -regtest generatetoaddress 1 "$MINER_ADDR"

TX_DETAIL=$(bitcoin-cli -regtest gettransaction "$TXID")
AMOUNT_IN=$(echo $TX_DETAIL | jq '.amount')
FEE=$(echo $TX_DETAIL | jq '.fee')
BLOCKHASH=$(echo $TX_DETAIL | jq -r '.blockhash')
BLOCKHEIGHT=$(bitcoin-cli -regtest getblockheader "$BLOCKHASH" | jq '.height')

RAW_TX=$(bitcoin-cli -regtest getrawtransaction "$TXID" true)
TO_ADDR=$(echo "$RAW_TX" | jq -r '.vout[0].scriptPubKey.addresses[0]')
AMOUNT_OUT=$(echo "$RAW_TX" | jq '.vout[0].value')
CHANGE_ADDR=$(echo "$RAW_TX" | jq -r '.vout[1].scriptPubKey.addresses[0]')
CHANGE_AMOUNT=$(echo "$RAW_TX" | jq '.vout[1].value')

MINER_BAL=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
TRADER_BAL=$(bitcoin-cli -regtest -rpcwallet=Trader getbalance)

echo ""
echo " DETALLES DE LA TRANSACCIÓN:"
echo "txid: $TXID"
echo "De, Cantidad: $MINER_ADDR, $AMOUNT_IN BTC"
echo "Enviar, Cantidad: $TO_ADDR, $AMOUNT_OUT BTC"
echo "Cambio, Cantidad: $CHANGE_ADDR, $CHANGE_AMOUNT BTC"
echo "Comisiones: $FEE BTC"
echo "Bloque: Altura $BLOCKHEIGHT"
echo "Saldo de Miner: $MINER_BAL BTC"
echo "Saldo de Trader: $TRADER_BAL BTC"
