#!/bin/bash

set -e

BITCOIN_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"
FLAG_FILE="/tmp/btc-rbf.running"

cleanup() {
  echo "🧹 Cleaning up environment..."
  if [ -f "$FLAG_FILE" ]; then
    bitcoin-cli -regtest stop 2>/dev/null || true
    sleep 2
  fi
  rm -rf "$BITCOIN_DIR/regtest"
  rm -f "$FLAG_FILE"
}
trap cleanup EXIT

start_bitcoind() {
  echo "🚀 Starting bitcoind..."
  bitcoind -regtest -daemon
  sleep 5
  bitcoin-cli -regtest getblockchaininfo > /dev/null
  touch "$FLAG_FILE"
}

create_wallets() {
  echo "🔐 Creating wallets..."
  bitcoin-cli -regtest createwallet "$MINER_WALLET" false false "" false true true > /dev/null
  bitcoin-cli -regtest createwallet "$TRADER_WALLET" false false "" false true true > /dev/null
}

generate_initial_coins() {
  echo "⛏️ Generating initial blocks..."
  MINER_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" getnewaddress "Reward")
  bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" generatetoaddress 103 "$MINER_ADDRESS" > /dev/null
  echo "🏦 Miner address: $MINER_ADDRESS"

  TRADER_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="$TRADER_WALLET" getnewaddress "Receive")
  echo "📬 Trader address: $TRADER_ADDRESS"
}

create_and_send_parent_tx() {
  echo "💸 Creating and sending Parent transaction..."
  UTXOS=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" listunspent | jq '.[:2]')
  TXID0=$(echo "$UTXOS" | jq -r '.[0].txid')
  VOUT0=$(echo "$UTXOS" | jq -r '.[0].vout')
  TXID1=$(echo "$UTXOS" | jq -r '.[1].txid')
  VOUT1=$(echo "$UTXOS" | jq -r '.[1].vout')

  RAW_TX=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$TXID0\",\"vout\":$VOUT0},{\"txid\":\"$TXID1\",\"vout\":$VOUT1}]" \
    "{\"$TRADER_ADDRESS\":70, \"$MINER_ADDRESS\":29.99999}")

  SIGNED_TX=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" signrawtransactionwithwallet "$RAW_TX" | jq -r '.hex')
  bitcoin-cli -regtest sendrawtransaction "$SIGNED_TX" > /dev/null

  PARENT_TXID=$(bitcoin-cli -regtest decoderawtransaction "$RAW_TX" | jq -r '.txid')
  echo "🧾 Parent txid: $PARENT_TXID"

  echo "$TXID0,$VOUT0,$TXID1,$VOUT1,$PARENT_TXID" > /tmp/parentinfo
}

create_and_send_child_tx() {
  echo "👶 Creating Child transaction..."
  MINER_CHILD_ADDR=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" getnewaddress "Child")
  TX_VOUT=$(bitcoin-cli -regtest decoderawtransaction "$SIGNED_TX" | jq '.vout[1]')
  OUT_PARENT_TXID=$(echo "$SIGNED_TX" | jq -r '.txid')
  VOUT_CHILD=$(echo "$TX_VOUT" | jq -r '.n')

  CHILD_RAW=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$PARENT_TXID\",\"vout\":$VOUT_CHILD}]" \
    "{\"$MINER_CHILD_ADDR\":29.99998}")
  CHILD_SIGNED=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" signrawtransactionwithwallet "$CHILD_RAW" | jq -r '.hex')
  CHILD_TXID=$(bitcoin-cli -regtest sendrawtransaction "$CHILD_SIGNED")

  echo "👶 Child txid: $CHILD_TXID"
  echo "$CHILD_TXID" > /tmp/childtxid

  echo -e "\n📄 getmempoolentry (Child):"
  bitcoin-cli -regtest getmempoolentry "$CHILD_TXID"
}

replace_parent_with_rbf() {
  echo "🔁 Replacing Parent with RBF transaction..."
  read TXID0 VOUT0 TXID1 VOUT1 _ < <(tr ',' ' ' < /tmp/parentinfo)

  RBF_RAW=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$TXID0\",\"vout\":$VOUT0},{\"txid\":\"$TXID1\",\"vout\":$VOUT1}]" \
    "{\"$TRADER_ADDRESS\":70, \"$MINER_ADDRESS\":29.99989}")
  RBF_SIGNED=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" signrawtransactionwithwallet "$RBF_RAW" | jq -r '.hex')
  RBF_TXID=$(bitcoin-cli -regtest sendrawtransaction "$RBF_SIGNED")

  echo "🆕 RBF txid: $RBF_TXID"

  echo -e "\n📄 getmempoolentry (Child after RBF):"
  CHILD_TXID=$(< /tmp/childtxid)
  if ! bitcoin-cli -regtest getmempoolentry "$CHILD_TXID"; then
    echo -e "❌ Child transaction was removed from the mempool."
  fi

  echo -e "\n📥 Current mempool:"
  bitcoin-cli -regtest getrawmempool true | jq
}

main() {
  echo "🏁 Starting RBF Script on Regtest"

  cleanup
  start_bitcoind
  create_wallets
  generate_initial_coins
  create_and_send_parent_tx
  create_and_send_child_tx
  replace_parent_with_rbf

  echo -e "\n✅ Process completed."
}

main
