#!/bin/bash
set -euo pipefail

DATA_DIR="$HOME/.bitcoin"
CONF_FILE="$DATA_DIR/bitcoin.conf"
BITCOIN_CLI="bitcoin-cli -regtest"

echo "> Configurando entorno en $DATA_DIR..."
mkdir -p "$DATA_DIR"
cat > "$CONF_FILE" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

echo "> Reiniciando bitcoind si está activo..."
if pgrep -x "bitcoind" > /dev/null; then
  $BITCOIN_CLI stop
  sleep 3
fi

echo "> Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 3

echo "> Verificando billeteras Miner y Trader..."
for WALLET in Miner Trader; do
  WALLET_PATH="$DATA_DIR/regtest/wallets/$WALLET"
  if $BITCOIN_CLI -rpcwallet="$WALLET" getwalletinfo &> /dev/null; then
    echo "> '$WALLET' ya cargada."
  elif [ -d "$WALLET_PATH" ]; then
    echo "> '$WALLET' existe. Cargando..."
    $BITCOIN_CLI loadwallet "$WALLET"
  else
    echo "> Creando '$WALLET'..."
    $BITCOIN_CLI createwallet "$WALLET"
  fi
done

MINER_ADDR=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress "Miner")

echo "> Minando hasta que Miner tenga al menos 150 BTC disponibles..."
SALDO=0
while (( $(echo "$SALDO < 150" | bc -l) )); do
  $BITCOIN_CLI generatetoaddress 10 "$MINER_ADDR" > /dev/null
  SALDO=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
  echo "  > Saldo actual: $SALDO BTC"
done

TRADER_ADDR=$($BITCOIN_CLI -rpcwallet=Trader getnewaddress "Trader")
echo "> Creando transacción padre (parent)..."

UTXOS=$($BITCOIN_CLI -rpcwallet=Miner listunspent | jq -c '[.[] | select(.amount==50)][:2]')

RAWTX=$($BITCOIN_CLI -named createrawtransaction \
  inputs="$UTXOS" \
  outputs="{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.99999}" \
  replaceable=true)

SIGNEDTX=$($BITCOIN_CLI -rpcwallet=Miner signrawtransactionwithwallet "$RAWTX" | jq -r '.hex')

PARENT_TXID=$($BITCOIN_CLI sendrawtransaction "$SIGNEDTX")
echo "> Parent TXID: $PARENT_TXID"

echo "> Detalles de transacción padre..."
sleep 3
PARENT_INFO=$($BITCOIN_CLI getmempoolentry "$PARENT_TXID")

miner_script=$($BITCOIN_CLI -rpcwallet=Miner getaddressinfo "$MINER_ADDR" | jq -r '.scriptPubKey')
trader_script=$($BITCOIN_CLI -rpcwallet=Trader getaddressinfo "$TRADER_ADDR" | jq -r '.scriptPubKey')

TX_JSON=$(jq -n \
  --arg txid1 "$(echo "$UTXOS" | jq -r '.[0].txid')" \
  --arg vout1 "$(echo "$UTXOS" | jq -r '.[0].vout')" \
  --arg txid2 "$(echo "$UTXOS" | jq -r '.[1].txid')" \
  --arg vout2 "$(echo "$UTXOS" | jq -r '.[1].vout')" \
  --arg miner_script "$miner_script" \
  --arg trader_script "$trader_script" \
  --argjson fees "$(echo "$PARENT_INFO" | jq '.fees.base // 0')" \
  --argjson weight "$(echo "$PARENT_INFO" | jq '.weight // 0')" \
  '{
    "input": [
      {"txid": $txid1, "vout": ($vout1 | tonumber)},
      {"txid": $txid2, "vout": ($vout2 | tonumber)}
    ],
    "output": [
      {"script_pubkey": $miner_script, "amount": "29.99999"},
      {"script_pubkey": $trader_script, "amount": "70.0"}
    ],
    "Fees": ($fees * 100000000 | floor),
    "Weight": $weight
  }')

echo "> JSON de transacción padre:"
echo "$TX_JSON" | jq

echo "> Creando transacción hija (child)..."
CHILD_ADDR=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress)
CHILD_RAWTX=$($BITCOIN_CLI -named createrawtransaction \
  inputs="[{\"txid\":\"$PARENT_TXID\",\"vout\":1}]" \
  outputs="{\"$CHILD_ADDR\":29.99998}")

CHILD_SIGNED=$($BITCOIN_CLI -rpcwallet=Miner signrawtransactionwithwallet "$CHILD_RAWTX" | jq -r '.hex')
CHILD_TXID=$($BITCOIN_CLI sendrawtransaction "$CHILD_SIGNED")

echo "> Estado de transacción hija (antes de RBF):"
CHILD_INFO_BEFORE=$($BITCOIN_CLI getmempoolentry "$CHILD_TXID")
echo "$CHILD_INFO_BEFORE" | jq

echo "> Creando reemplazo RBF de transacción padre..."
RBF_RAWTX=$($BITCOIN_CLI -named createrawtransaction \
  inputs="$UTXOS" \
  outputs="{\"$TRADER_ADDR\":69.99999,\"$MINER_ADDR\":29.99990}" \
  replaceable=true)

RBF_SIGNED=$($BITCOIN_CLI -rpcwallet=Miner signrawtransactionwithwallet "$RBF_RAWTX" | jq -r '.hex')
RBF_TXID=$($BITCOIN_CLI sendrawtransaction "$RBF_SIGNED")

echo "> Verificando existencia de transacción hija luego del RBF..."
if ! $BITCOIN_CLI getmempoolentry "$CHILD_TXID" 2>/dev/null; then
  echo "❌ La transacción hija fue eliminada del mempool: su input fue invalidado por el reemplazo de la transacción padre (RBF)."
else
  echo "⚠️ La transacción hija aún está en el mempool (revisar comportamiento del nodo)."
fi

echo "> Confirmando nueva transacción padre:"
$BITCOIN_CLI getmempoolentry "$RBF_TXID" | jq

echo "✅ Script finalizado con éxito."
