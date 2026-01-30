#!/bin/bash

# Bitcoin Core Regtest Setup Script (v29.0)

set -e

BITCOIN_VER="29.0"
DATA_DIR="$HOME/.bitcoin"
TMP_DIR="/tmp/btc-setup"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"
FLAG_FILE="$TMP_DIR/node.running"

cleanup() {
  if [ -f "$FLAG_FILE" ]; then
    bitcoin-cli -regtest stop 2>/dev/null || true
    sleep 2
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

install_dependencies() {
  command -v jq >/dev/null || sudo apt-get update && sudo apt-get install -y jq
  command -v bc >/dev/null || sudo apt-get install -y bc
}

download_and_install() {
  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VER/bitcoin-$BITCOIN_VER-x86_64-linux-gnu.tar.gz"
  wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VER/SHA256SUMS"
  wget "https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VER/SHA256SUMS.asc"

  sha256sum -c --ignore-missing SHA256SUMS | grep "bitcoin-$BITCOIN_VER-x86_64-linux-gnu.tar.gz: OK" >/dev/null ||
    {
      echo "Hash verification failed"
      exit 1
    }

  tar -xzf "bitcoin-$BITCOIN_VER-x86_64-linux-gnu.tar.gz"
  sudo cp "bitcoin-$BITCOIN_VER/bin/"* /usr/local/bin/
}

initialize_config() {
  bitcoin-cli -regtest stop 2>/dev/null || true
  sleep 3
  rm -rf "$DATA_DIR/regtest"
  mkdir -p "$DATA_DIR"

  cat >"$DATA_DIR/bitcoin.conf" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
descriptors=1
EOF
}

start_bitcoind() {
  bitcoind -regtest -daemon
  sleep 5
  bitcoin-cli -regtest getblockchaininfo >/dev/null || {
    echo "Daemon startup failed"
    exit 1
  }
  touch "$FLAG_FILE"
}

create_wallets() {
  bitcoin-cli -regtest createwallet "$MINER_WALLET" false false "" false true true
  bitcoin-cli -regtest createwallet "$TRADER_WALLET" false false "" false true true
}

generate_initial_funds() {
  MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" getnewaddress)
  blocks=0

  while true; do
    bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" generatetoaddress 1 "$MINER_ADDR" >/dev/null
    blocks=$((blocks + 1))
    balance=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" getbalance)

    if (($(echo "$balance > 0" | bc -l))); then
      break
    fi

    [ $blocks -gt 150 ] && {
      echo "Mining loop exceeded"
      exit 1
    }
  done
}

send_transaction() {
  RECEIVER_ADDR=$(bitcoin-cli -regtest -rpcwallet="$TRADER_WALLET" getnewaddress)
  TXID=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" sendtoaddress "$RECEIVER_ADDR" 20)
  bitcoin-cli -regtest getmempoolentry "$TXID" >/dev/null

  bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" generatetoaddress 1 "$MINER_ADDR" >/dev/null

  RAW_TX=$(bitcoin-cli -regtest getrawtransaction "$TXID" true)
  BLOCK_HASH=$(echo "$RAW_TX" | jq -r '.blockhash')
  BLOCK_INFO=$(bitcoin-cli -regtest getblock "$BLOCK_HASH")
  BLOCK_HEIGHT=$(echo "$BLOCK_INFO" | jq -r '.height')

  IN_ADDR=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" listunspent | jq -r '.[0].address' 2>/dev/null || echo "$MINER_ADDR")
  INPUT_AMT=$(echo "$RAW_TX" | jq -r '.vin[0].prevout.value // "0"')
  CHANGE_AMT=$(echo "$RAW_TX" | jq -r --arg addr "$MINER_ADDR" '.vout[] | select(.scriptPubKey.address == $addr) | .value' | head -1)
  FEE=$(echo "$INPUT_AMT - (20 + $CHANGE_AMT)" | bc -l)

  BAL_MINER=$(bitcoin-cli -regtest -rpcwallet="$MINER_WALLET" getbalance)
  BAL_TRADER=$(bitcoin-cli -regtest -rpcwallet="$TRADER_WALLET" getbalance)

  echo "txid: $TXID"
  echo "from: $IN_ADDR, amount: $INPUT_AMT"
  echo "to: $RECEIVER_ADDR, amount: 20"
  echo "change: $MINER_ADDR, amount: $CHANGE_AMT"
  echo "fee: $FEE"
  echo "block height: $BLOCK_HEIGHT"
  echo "Miner balance: $BAL_MINER"
  echo "Trader balance: $BAL_TRADER"
}

main() {
  install_dependencies
  download_and_install
  initialize_config
  start_bitcoind
  create_wallets
  generate_initial_funds
  send_transaction
  rm -f "$FLAG_FILE"
}

main
