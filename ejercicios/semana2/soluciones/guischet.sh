#!/bin/bash

# Exit on error
set -e

# ==============================================================================
# Week 2: RBF and CPFP Fee Bumping Demo
# ==============================================================================
VERSION="29.0"
OS="x86_64-linux-gnu"
FILENAME="bitcoin-${VERSION}-${OS}.tar.gz"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${VERSION}"

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
echo "Binary verification successful"

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

pkill -9 bitcoind || true
sleep 1

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

alias btc="bitcoin-cli -datadir=$DATA_DIR -regtest -rpcuser=user -rpcpassword=password"
shopt -s expand_aliases

# ==============================================================================
echo "--- Step 4 (1): Create Wallets ---"
btc createwallet "Miner" > /dev/null
btc createwallet "Trader" > /dev/null
echo "Wallets created: Miner, Trader"

# ==============================================================================
echo "--- Step 4 (2): Fund Miner ---"
# Mine 103 blocks so the first 3 coinbase rewards become mature (100 confirmations each).
# Mature UTXOs: blocks 1, 2, 3 → each 50 BTC → total 150 BTC spendable
MINER_ADDR=$(btc -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining 103 blocks to $MINER_ADDR..."
btc generatetoaddress 103 "$MINER_ADDR" > /dev/null
echo "Miner balance: $(btc -rpcwallet=Miner getbalance) BTC"

# ==============================================================================
echo "--- Step 5 (3): Craft Parent Transaction with RBF ---"

# Pick exactly 2 mature UTXOs (each 50 BTC) from Miner
UTXOS=$(btc -rpcwallet=Miner listunspent 1)
UTXO0=$(echo "$UTXOS" | jq '.[0]')
UTXO1=$(echo "$UTXOS" | jq '.[1]')

TXID0=$(echo "$UTXO0" | jq -r '.txid')
VOUT0=$(echo "$UTXO0" | jq -r '.vout')
TXID1=$(echo "$UTXO1" | jq -r '.txid')
VOUT1=$(echo "$UTXO1" | jq -r '.vout')

echo "UTXO[0]: $TXID0:$VOUT0 ($(echo "$UTXO0" | jq -r '.amount') BTC)"
echo "UTXO[1]: $TXID1:$VOUT1 ($(echo "$UTXO1" | jq -r '.amount') BTC)"

TRADER_ADDR=$(btc -rpcwallet=Trader getnewaddress "Received")
MINER_CHANGE_ADDR=$(btc -rpcwallet=Miner getnewaddress "Change")

# Parent tx structure:
#   Input[0]:  50 BTC coinbase (UTXO0), sequence=1 → signals RBF (BIP125)
#   Input[1]:  50 BTC coinbase (UTXO1), sequence=1 → signals RBF (BIP125)
#   Output[0]: 70 BTC  → Trader
#   Output[1]: 29.99999 BTC → Miner (change)
#   Fee:       100 - 99.99999 = 0.00001 BTC = 1000 sats
RAW_PARENT=$(btc createrawtransaction \
    "[{\"txid\":\"$TXID0\",\"vout\":$VOUT0,\"sequence\":1},{\"txid\":\"$TXID1\",\"vout\":$VOUT1,\"sequence\":1}]" \
    "{\"$TRADER_ADDR\":70,\"$MINER_CHANGE_ADDR\":29.99999}")

# ==============================================================================
echo "--- Step 6 (4): Sign and Broadcast Parent ---"
SIGNED_PARENT_JSON=$(btc -rpcwallet=Miner signrawtransactionwithwallet "$RAW_PARENT")
SIGNED_PARENT_HEX=$(echo "$SIGNED_PARENT_JSON" | jq -r '.hex')

[ "$(echo "$SIGNED_PARENT_JSON" | jq -r '.complete')" = "true" ] \
    || { echo "ERROR: Parent signing incomplete"; exit 1; }

PARENT_TXID=$(btc sendrawtransaction "$SIGNED_PARENT_HEX")
echo "Parent TX broadcast (unconfirmed): $PARENT_TXID"

# ==============================================================================
echo "--- Step 7 (5-6): Query Mempool & Print Parent JSON ---"

MEMPOOL_ENTRY=$(btc getmempoolentry "$PARENT_TXID")
RAW_PARENT_TX=$(btc getrawtransaction "$PARENT_TXID" true)

# Inputs
IN0_TXID=$(echo "$RAW_PARENT_TX" | jq -r '.vin[0].txid')
IN0_VOUT=$(echo "$RAW_PARENT_TX" | jq '.vin[0].vout')
IN1_TXID=$(echo "$RAW_PARENT_TX" | jq -r '.vin[1].txid')
IN1_VOUT=$(echo "$RAW_PARENT_TX" | jq '.vin[1].vout')

# Outputs (vout[0]=Trader 70 BTC, vout[1]=Miner change 29.99999 BTC)
OUT0_SPK=$(echo "$RAW_PARENT_TX" | jq -r '.vout[0].scriptPubKey.hex')
OUT0_AMT=$(echo "$RAW_PARENT_TX" | jq -r '.vout[0].value | tostring')
OUT1_SPK=$(echo "$RAW_PARENT_TX" | jq -r '.vout[1].scriptPubKey.hex')
OUT1_AMT=$(echo "$RAW_PARENT_TX" | jq -r '.vout[1].value | tostring')

# Fee (in BTC) and Weight (in vbytes)
FEES=$(echo "$MEMPOOL_ENTRY" | jq -r '.fees.base | tostring')
VSIZE=$(echo "$RAW_PARENT_TX" | jq '.vsize')

PARENT_JSON=$(jq -n \
    --arg in0_txid  "$IN0_TXID" \
    --argjson in0_vout "$IN0_VOUT" \
    --arg in1_txid  "$IN1_TXID" \
    --argjson in1_vout "$IN1_VOUT" \
    --arg out0_spk  "$OUT0_SPK" \
    --arg out0_amt  "$OUT0_AMT" \
    --arg out1_spk  "$OUT1_SPK" \
    --arg out1_amt  "$OUT1_AMT" \
    --arg fees      "$FEES" \
    --argjson weight "$VSIZE" \
    '{
        "input": [
            {"txid": $in0_txid, "vout": $in0_vout},
            {"txid": $in1_txid, "vout": $in1_vout}
        ],
        "output": [
            {"script_pubkey": $out0_spk, "amount": $out0_amt},
            {"script_pubkey": $out1_spk, "amount": $out1_amt}
        ],
        "Fees": $fees,
        "Weight": $weight
    }')

echo "Parent TX JSON:"
echo "$PARENT_JSON"

# ==============================================================================
echo "--- Step 8 (7): Create Child Transaction ---"

# Child spends Miner's change output (vout[1]) from the Parent
MINER_VOUT=$(echo "$RAW_PARENT_TX" | \
    jq -r --arg addr "$MINER_CHANGE_ADDR" '.vout[] | select(.scriptPubKey.address == $addr) | .n')
MINER_NEW_ADDR=$(btc -rpcwallet=Miner getnewaddress "CPFP")

echo "Miner's change is at vout=$MINER_VOUT in Parent TX"

# Child tx:
#   Input[0]:  Miner's change output from Parent (29.99999 BTC)
#   Output[0]: New Miner address, 29.99998 BTC
#   Fee:       0.00001 BTC = 1000 sats
RAW_CHILD=$(btc createrawtransaction \
    "[{\"txid\":\"$PARENT_TXID\",\"vout\":$MINER_VOUT}]" \
    "{\"$MINER_NEW_ADDR\":29.99998}")

SIGNED_CHILD_JSON=$(btc -rpcwallet=Miner signrawtransactionwithwallet "$RAW_CHILD")
CHILD_HEX=$(echo "$SIGNED_CHILD_JSON" | jq -r '.hex')

[ "$(echo "$SIGNED_CHILD_JSON" | jq -r '.complete')" = "true" ] \
    || { echo "ERROR: Child signing incomplete"; exit 1; }

CHILD_TXID=$(btc sendrawtransaction "$CHILD_HEX")
echo "Child TX broadcast: $CHILD_TXID"

# ==============================================================================
echo "--- Step 9 (8): getmempoolentry for Child BEFORE RBF ---"
echo "Child mempool entry BEFORE RBF:"
btc getmempoolentry "$CHILD_TXID"

# ==============================================================================
echo "--- Step 10 (9-10): Fee Bump Parent via Manual RBF ---"

# Original Parent fee:  100 - 99.99999 = 0.00001 BTC = 1,000 sats
# Bump by 10,000 sats   = +0.0001 BTC
# New fee:              0.00011 BTC = 11,000 sats
# New Miner change:     29.99999 - 0.0001 = 29.99989 BTC
#
# Same inputs (TXID0:VOUT0, TXID1:VOUT1) → creates conflicting tx
# Trader output stays 70 BTC (unchanged)
RBF_MINER_ADDR=$(btc -rpcwallet=Miner getnewaddress "RBF Change")

RAW_RBF=$(btc createrawtransaction \
    "[{\"txid\":\"$TXID0\",\"vout\":$VOUT0,\"sequence\":1},{\"txid\":\"$TXID1\",\"vout\":$VOUT1,\"sequence\":1}]" \
    "{\"$TRADER_ADDR\":70,\"$RBF_MINER_ADDR\":29.99989}")

SIGNED_RBF_JSON=$(btc -rpcwallet=Miner signrawtransactionwithwallet "$RAW_RBF")
RBF_HEX=$(echo "$SIGNED_RBF_JSON" | jq -r '.hex')

[ "$(echo "$SIGNED_RBF_JSON" | jq -r '.complete')" = "true" ] \
    || { echo "ERROR: RBF signing incomplete"; exit 1; }

RBF_TXID=$(btc sendrawtransaction "$RBF_HEX")
echo "RBF (new Parent) TX broadcast: $RBF_TXID"
echo "Original Parent $PARENT_TXID has been REPLACED"

# ==============================================================================
echo "--- Step 11: getmempoolentry for Child AFTER RBF ---"
echo "Child mempool entry AFTER RBF:"
set +e
CHILD_AFTER=$(btc getmempoolentry "$CHILD_TXID" 2>&1)
CHILD_STATUS=$?
set -e

if [ $CHILD_STATUS -ne 0 ]; then
    echo "ERROR returned: $CHILD_AFTER"
    echo "(Child TX was evicted from the mempool)"
else
    echo "$CHILD_AFTER"
fi


btc stop > /dev/null
echo "Node stopped."
