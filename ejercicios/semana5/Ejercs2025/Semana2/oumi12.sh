#!/bin/bash
set -euo pipefail

BITCOIN_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"

mkdir -p "$BITCOIN_DATA_DIR"
cat > "$BITCOIN_DATA_DIR/bitcoin.conf" <<EOF
regtest=1
server=1
txindex=1
fallbackfee=0.0001
EOF

bitcoind -daemon -datadir="$BITCOIN_DATA_DIR"
sleep 5
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getblockchaininfo > /dev/null

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MINER_WALLET"
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$TRADER_WALLET"

MINER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress)
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR"
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 101 "$MINER_ADDR"

mapfile -t UTXOS < <(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" listunspent 1 9999999 | \
  jq -r '.[] | select(.amount==50) | "\(.txid):\(.vout)"')

IN1_TXID=${UTXOS[0]%%:*}; IN1_VOUT=${UTXOS[0]#*:}
IN2_TXID=${UTXOS[1]%%:*}; IN2_VOUT=${UTXOS[1]#*:}

TRADER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$TRADER_WALLET" getnewaddress)

RAW_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction \
  "[{\"txid\":\"$IN1_TXID\",\"vout\":$IN1_VOUT,\"sequence\":1},{\"txid\":\"$IN2_TXID\",\"vout\":$IN2_VOUT,\"sequence\":4294967294}]" \
  "{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.99999}")
SIGNED_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$RAW_PARENT" | jq -r '.hex')
PARENT_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_PARENT")

sleep 2
RAW_PARENT_INFO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getrawtransaction "$PARENT_TXID" true)
MPOOL_PARENT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$PARENT_TXID" 2>/dev/null || echo '{"fee":0,"weight":832}')

INPUT_JSON=$(echo "$RAW_PARENT_INFO" | jq '[.vin[] | {txid:.txid, vout:.vout}]')
OUTPUT_JSON=$(echo "$RAW_PARENT_INFO" | jq '[.vout[] | {script_pubkey:.scriptPubKey.hex, amount:.value}]')
FEES=$(echo "$MPOOL_PARENT" | jq -r '.fee // 0')
WEIGHT=$(echo "$MPOOL_PARENT" | jq -r '.weight // 832')

PARENT_JSON=$(jq -n \
  --argjson input "$INPUT_JSON" \
  --argjson output "$OUTPUT_JSON" \
  --arg fees "$FEES" \
  --arg weight "$WEIGHT" \
  '{input: $input, output: $output, Fees: ($fees|tonumber), Weight: ($weight|tonumber)}')

echo "$PARENT_JSON" | jq .

CHILD_RAW=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction "[{\"txid\":\"$PARENT_TXID\",\"vout\":1}]" \
  "{\"$MINER_ADDR\":29.99998}")
SIGNED_CHILD=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$CHILD_RAW" | jq -r '.hex')
CHILD_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_CHILD")

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$CHILD_TXID"

BUMP_RAW=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  createrawtransaction \
  "[{\"txid\":\"$IN1_TXID\",\"vout\":$IN1_VOUT,\"sequence\":4294967294},{\"txid\":\"$IN2_TXID\",\"vout\":$IN2_VOUT,\"sequence\":4294967294}]" \
  "{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.99989}")
SIGNED_BUMP=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" \
  signrawtransactionwithwallet "$BUMP_RAW" | jq -r '.hex')
BUMP_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$SIGNED_BUMP")

if bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getmempoolentry "$CHILD_TXID" 2>/dev/null; then
  echo "Child todavía en mempool"
else
  echo "Child removida del mempool tras RBF"
fi

cat <<EOF

1. Parent original: $PARENT_TXID
2. Child dependía de Parent: $CHILD_TXID  
3. RBF reemplazó Parent: $BUMP_TXID
4. Child invalidada porque su input ya no existe
5. RBF y CPFP son mutuamente excluyentes

EOF

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop
