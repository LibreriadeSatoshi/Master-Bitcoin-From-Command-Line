#!/bin/bash
set -euo pipefail

BITCOIN_VERSION="29.0"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION"
DATA_DIR="$HOME/.bitcoin"
CONF_FILE="$DATA_DIR/bitcoin.conf"

BIN_NAME="bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz"

echo "> Descargando binarios de Bitcoin Core v$BITCOIN_VERSION..."
wget -nc "$BITCOIN_URL/$BIN_NAME"
wget -nc "$BITCOIN_URL/SHA256SUMS"
wget -nc "$BITCOIN_URL/SHA256SUMS.asc"

echo "🔐 Verificando la firma de los hashes..."

# Clonar el repositorio oficial de claves de los builders de Bitcoin Core
if [ ! -d "guix.sigs" ]; then
  git clone https://github.com/bitcoin-core/guix.sigs
fi

# Importar todas las claves públicas
find guix.sigs/builder-keys -name '*.gpg' -exec gpg --import {} +

gpg --verify SHA256SUMS.asc SHA256SUMS

echo "> Verificando hash de binario..."
sha256sum --ignore-missing -c SHA256SUMS 2>/dev/null | grep "$BIN_NAME: OK"
echo "> Verificación exitosa de la firma binaria."

echo "> Extrayendo binarios..."
tar -xzf "$BIN_NAME"
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-$BITCOIN_VERSION/bin/*

echo "> Configurando bitcoin.conf en $DATA_DIR..."
mkdir -p "$DATA_DIR"
cat > "$CONF_FILE" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

echo "> Verificando si hay procesos de bitcoind activos..."
if pgrep -x "bitcoind" > /dev/null; then
  echo "> Se encontró un proceso de bitcoind. Deteniéndolo..."
  pkill -x bitcoind
  sleep 2
fi

echo "> Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 3

echo "> Verificando billeteras Miner y Trader..."

for WALLET in Miner Trader; do
  WALLET_PATH="$DATA_DIR/regtest/wallets/$WALLET"
  if bitcoin-cli -regtest -rpcwallet="$WALLET" getwalletinfo &> /dev/null; then
    echo "> Billetera '$WALLET' ya está cargada."
  elif [ -d "$WALLET_PATH" ]; then
    echo "> Billetera '$WALLET' existe en disco. Cargando..."
    bitcoin-cli -regtest loadwallet "$WALLET"
  else
    echo "> Creando billetera '$WALLET'..."
    bitcoin-cli -regtest createwallet "$WALLET"
  fi
done

if ! bitcoin-cli -regtest -rpcwallet=Trader getwalletinfo &> /dev/null; then
  bitcoin-cli -regtest createwallet Trader
else
  echo "> La billetera Trader ya existe. Omitiendo..."
fi

MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Recompensa")
echo "> Minando hasta obtener saldo positivo..."

blocks=0
balance=0
command -v bc >/dev/null 2>&1 || { echo >&2 "❌ Error: 'bc' no está instalado. Ejecuta: sudo apt install bc"; exit 1; }
while [ "$balance" = "0.00000000" ]; do
  bitcoin-cli -regtest generatetoaddress 1 "$MINER_ADDR" > /dev/null
  sleep 0.2
  balance=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance || echo 0)
  ((blocks++))
done

echo "> $blocks bloques minados. Saldo Miner: $balance BTC"

TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Receptor")
echo "> Enviando 20 BTC de Miner a Trader..."
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)

echo "> Buscando la transacción en el mempool..."
sleep 1
bitcoin-cli -regtest -rpcwallet=Miner getmempoolentry "$TXID"

echo "> Confirmando transacción minando un bloque..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" > /dev/null
sleep 1

# Minar 100 para maduración y fees futuras
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 100 "$MINER_ADDR" > /dev/null

RAW_TX=$(bitcoin-cli -regtest -rpcwallet=Miner gettransaction "$TXID" true)
TX_HEX=$(echo "$RAW_TX" | jq -r '.hex')
TX_DECODED=$(bitcoin-cli -regtest -rpcwallet=Miner decoderawtransaction "$TX_HEX")
BLOCK_HASH=$(echo "$RAW_TX" | jq -r '.blockhash')
BLOCK_HEIGHT=$(bitcoin-cli -regtest -rpcwallet=Miner getblock "$BLOCK_HASH" | jq -r '.height')
FEE=$(echo "$RAW_TX" | jq '.fee' | awk '{print -$1}')
IN_VALUE=$(echo "$TX_DECODED" | jq '[.vin[]] | length')
OUT_TOTAL=$(echo "$TX_DECODED" | jq '[.vout[].value] | add')
CHANGE=$(echo "$OUT_TOTAL - 20" | bc)

echo "> Resultado:"
echo "- txid: $TXID"
echo "- Entradas: $IN_VALUE"
echo "- Enviado: 20 BTC"
echo "- Cambio: $CHANGE BTC"
echo "- Fee: $FEE BTC"
echo "- Bloque altura: $BLOCK_HEIGHT"
echo "- Saldo Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
echo "- Saldo Trader: $(bitcoin-cli -regtest -rpcwallet=Trader getbalance) BTC"

echo "> Script finalizado con éxito. 🟢"

