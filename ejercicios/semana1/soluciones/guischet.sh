#!/bin/bash

# Exit on error
set -e

# ==============================================================================
VERSION="29.0"
OS="x86_64-linux-gnu"
FILENAME="bitcoin-${VERSION}-${OS}.tar.gz"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${VERSION}"

# Directories
ROOT_DIR=$(pwd)
BIN_DIR="$ROOT_DIR/bitcoin_binaries"
DATA_DIR="$ROOT_DIR/btc_data"

echo "--- Step 1: Download and Verify ---"
mkdir -p "$BIN_DIR"
cd "$BIN_DIR"

if [ ! -f "$FILENAME" ]; then
    echo "Downloading Bitcoin Core $VERSION..."
    wget "${BASE_URL}/${FILENAME}"
    wget "${BASE_URL}/SHA256SUMS"
    wget "${BASE_URL}/SHA256SUMS.asc"
fi

sha256sum --ignore-missing --check SHA256SUMS
echo "Binary signature verification successful"

echo "--- Step 2: Setup Path ---"
if [ ! -d "bitcoin-${VERSION}" ]; then
    tar -xzf "$FILENAME"
fi
export PATH="$BIN_DIR/bitcoin-${VERSION}/bin:$PATH"

echo "--- Step 3: Configuration & Node Start ---"
rm -rf "$DATA_DIR" 
mkdir -p "$DATA_DIR"

cat <<EOF > "$DATA_DIR/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=user
rpcpassword=password
EOF

# Ensure no other bitcoind is blocking our port
pkill -9 bitcoind || true

bitcoind -datadir="$DATA_DIR" -daemon
echo "Waiting for node to be ready..."
for i in {1..30}; do
    if bitcoin-cli -datadir="$DATA_DIR" -regtest -rpcuser=user -rpcpassword=password getblockchaininfo > /dev/null 2>&1; then
        echo "Node is ready!"
        break
    fi
    [ $i -eq 30 ] && echo "Failed to start node." && exit 1
    sleep 1
done

# Helper for CLI calls
alias btc="bitcoin-cli -datadir=$DATA_DIR -regtest -rpcuser=user -rpcpassword=password"
shopt -s expand_aliases

echo "--- Step 4: Wallets and Mining ---"
btc createwallet "Miner" > /dev/null
btc createwallet "Trader" > /dev/null

MINER_ADDR=$(btc -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining 101 blocks to $MINER_ADDR..."
btc generatetoaddress 101 "$MINER_ADDR" > /dev/null

echo "Miner wallet balance: $(btc -rpcwallet=Miner getbalance) BTC"

echo "--- Step 5: Transaction ---"
TRADER_ADDR=$(btc -rpcwallet=Trader getnewaddress "Received")
TXID=$(btc -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)

echo "Unconfirmed transaction in mempool:"
btc getmempoolentry "$TXID"

echo "Confirming transaction..."
btc generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "--- Step 6: Final Details (we use SATOSHIS for math) ---"
TX_INFO=$(btc -rpcwallet=Miner gettransaction "$TXID")
RAW_TX=$(btc getrawtransaction "$TXID" true)

# Function to convert BTC string to Satoshis (Integer)
to_sats() {
    echo "$1" | LC_ALL=C awk '{printf "%.0f", $1 * 100000000}'
}

# Function to convert Satoshis to BTC string
to_btc() {
    echo "$1" | LC_ALL=C awk '{printf "%.8f", $1 / 100000000}'
}

# 1. Fees
FEES_BTC=$(echo "$TX_INFO" | jq -r '.fee | fabs')
FEES_SATS=$(to_sats "$FEES_BTC")

# 2. Input Amount (Sum of previous outputs)
INPUT_SATS=0
for row in $(echo "$RAW_TX" | jq -r '.vin[] | @base64'); do
    _jq() { echo ${row} | base64 --decode | jq -r ${1}; }
    PREV_TXID=$(_jq '.txid')
    VOUT_IDX=$(_jq '.vout')
    VOUT_VAL_BTC=$(btc getrawtransaction "$PREV_TXID" true | jq -r ".vout[$VOUT_IDX].value")
    VOUT_VAL_SATS=$(to_sats "$VOUT_VAL_BTC")
    INPUT_SATS=$((INPUT_SATS + VOUT_VAL_SATS))
done

# 3. Sent Amount (20 BTC)
SENT_SATS=$(to_sats "20.00000000")

# 4. Change Calculation
# Input - Sent - Fees = Change
CHANGE_SATS=$((INPUT_SATS - SENT_SATS - FEES_SATS))

# Metadata
BLOCK_HASH=$(echo "$TX_INFO" | jq -r '.blockhash')
BLOCK_HEIGHT=$(btc getblock "$BLOCK_HASH" | jq -r '.height')
CHANGE_ADDR=$(echo "$RAW_TX" | jq -r ".vout[] | select(.scriptPubKey.address != \"$TRADER_ADDR\") | .scriptPubKey.address")

MINER_BAL=$(btc -rpcwallet=Miner getbalance)
TRADER_BAL=$(btc -rpcwallet=Trader getbalance)

echo "--------------------------------------------------"
echo "txid: $TXID"
echo "<De, Cantidad>: $MINER_ADDR, $(to_btc $INPUT_SATS) BTC"
echo "<Enviar, Cantidad>: $TRADER_ADDR, $(to_btc $SENT_SATS) BTC"
echo "<Cambio, Cantidad>: $CHANGE_ADDR, $(to_btc $CHANGE_SATS) BTC"
echo "Comisiones: $(to_btc $FEES_SATS) BTC ($FEES_SATS sats)"
echo "Bloque: $BLOCK_HEIGHT"
echo "Saldo de Miner: $MINER_BAL BTC"
echo "Saldo de Trader: $TRADER_BAL BTC"
echo "--------------------------------------------------"

btc stop > /dev/null