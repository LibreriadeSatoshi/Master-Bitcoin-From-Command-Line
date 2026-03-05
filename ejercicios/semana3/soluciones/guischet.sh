#!/bin/bash

# Exit on error
set -e

# ==============================================================================
# Week 3: PSBT Multisig 2-of-2 Demo
# Approach: descriptor wallets + wsh(multi(2,...)) 
# Setup:
#   • Alice and Bob have standard descriptor wallets
#   • A watch-only descriptor wallet "Multisig" is created for the 2-of-2 addr
#   • Fund multisig with 10 BTC from Alice + 10 BTC from Bob via PSBT pooling
#
# Settle:
#   • Spend 3 BTC from multisig to Alice, rest to Bob
#   • Alice and Bob each sign the PSBT in parallel → combinepsbt → broadcast
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
# PARTE 1: SETUP MULTISIG
# ==============================================================================

echo ""
echo "======================================================================"
echo "  SETUP MULTISIG"
echo "======================================================================"

echo "--- Step 4 (1): Create Wallets: Miner, Alice, Bob ---"
btc createwallet "Miner" > /dev/null
btc createwallet "Alice" > /dev/null
btc createwallet "Bob"   > /dev/null
echo "Wallets created: Miner, Alice, Bob (all descriptor wallets)"

# ==============================================================================
echo "--- Step 5 (2): Fund Miner and send coins to Alice and Bob ---"

# Mine 103 blocks → 3 mature coinbase UTXOs
MINER_ADDR=$(btc -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining 103 blocks to Miner..."
btc generatetoaddress 103 "$MINER_ADDR" > /dev/null
echo "Miner balance: $(btc -rpcwallet=Miner getbalance) BTC"

# Send 20 BTC to Alice and 20 BTC to Bob (each contributes 10 to the multisig)
ALICE_ADDR=$(btc -rpcwallet=Alice getnewaddress "Received from Miner")
BOB_ADDR=$(btc   -rpcwallet=Bob   getnewaddress "Received from Miner")

echo "Sending 20 BTC to Alice ($ALICE_ADDR)..."
btc -rpcwallet=Miner sendtoaddress "$ALICE_ADDR" 20 > /dev/null

echo "Sending 20 BTC to Bob ($BOB_ADDR)..."
btc -rpcwallet=Miner sendtoaddress "$BOB_ADDR"   20 > /dev/null

# Mine 6 blocks to confirm the sends
btc generatetoaddress 6 "$MINER_ADDR" > /dev/null
echo "Alice balance: $(btc -rpcwallet=Alice getbalance) BTC"
echo "Bob   balance: $(btc -rpcwallet=Bob   getbalance) BTC"

# ==============================================================================
echo "--- Step 6 (3): Create 2-of-2 Multisig wallet using descriptors (LBTCL §3.5 & §7.2) ---"
#
#
#  a) Obtain the per-address descriptor from each signing wallet.
#     We include the full derivation info (xpub path) from getaddressinfo so
#     that the Multisig watch-only wallet knows the witness script.
#
#  b) Build a wsh(multi(2, descAlice, descBob)) output-descriptor.
#     getdescriptorinfo adds the checksum Bitcoin Core requires.
#
#  c) Create a blank, watch-only descriptor wallet called "Multisig".
#     It stores only the script; Alice and Bob keep their private keys.
#
#  d) importdescriptors into the Multisig wallet so it can:
#       • generate the multisig address (getnewaddress)
#       • track UTXOs sent to that address (listunspent)
#
#  e) Alice and Bob sign PSBTs from their own wallets (they hold the privkeys).

# ── a) Get a fresh address from each signing wallet
ALICE_NEWADDR=$(btc -rpcwallet=Alice getnewaddress "" bech32)
BOB_NEWADDR=$(btc   -rpcwallet=Bob   getnewaddress "" bech32)

# getaddressinfo returns the full descriptor including the HD derivation path
ALICE_DESC=$(btc -rpcwallet=Alice getaddressinfo "$ALICE_NEWADDR" | jq -r '.desc')
BOB_DESC=$(btc   -rpcwallet=Bob   getaddressinfo "$BOB_NEWADDR"   | jq -r '.desc')

echo "Alice descriptor: $ALICE_DESC"
echo "Bob   descriptor: $BOB_DESC"

# Strip the outer wpkh(...) and its checksum — we need just the key portion
# so we can embed it inside wsh(multi(...)).
# A wpkh descriptor looks like: wpkh([fingerprint/path]pubkey)#checksum
# We want the inner part: [fingerprint/path]pubkey
ALICE_KEY=$(echo "$ALICE_DESC" | sed 's/wpkh(\(.*\))#.*/\1/')
BOB_KEY=$(echo   "$BOB_DESC"   | sed 's/wpkh(\(.*\))#.*/\1/')

echo "Alice key: $ALICE_KEY"
echo "Bob   key: $BOB_KEY"

# ── b) Build the wsh(multi(2,...)) descriptor and get its checksum
RAW_MULTISIG_DESC="wsh(multi(2,$ALICE_KEY,$BOB_KEY))"
MULTISIG_DESC=$(btc getdescriptorinfo "$RAW_MULTISIG_DESC" | jq -r '.descriptor')
echo "Multisig descriptor: $MULTISIG_DESC"

# ── c) Create the "Multisig" wallet: blank + disable_private_keys + descriptors
#      (watch-only; Alice and Bob still hold their respective private keys)
btc createwallet "Multisig" true true "" false true > /dev/null
echo "Watch-only descriptor wallet 'Multisig' created."

# ── d) Import the wsh(multi(2,...)) descriptor into the Multisig wallet
btc -rpcwallet=Multisig importdescriptors \
    "[{\"desc\":\"$MULTISIG_DESC\",\"timestamp\":\"now\"}]" > /dev/null
echo "Multisig descriptor imported."

# Generate the multisig receiving address from the Multisig wallet
# Derive the multisig receiving address from the descriptor directly.
MULTISIG_ADDR=$(btc deriveaddresses "$MULTISIG_DESC" | jq -r '.[0]')
# (Alice and Bob's wallets don't need the multisig descriptor imported,

# ==============================================================================
echo "--- Step 7 (4): Create PSBT to fund Multisig (10 BTC from Alice + 10 BTC from Bob) ---"
# LBTCL §7.2 "trustless pooling": each party contributes one UTXO to the same
# PSBT; neither can steal from the other because neither will broadcast until

# Pick one UTXO from each wallet
ALICE_UTXO=$(btc -rpcwallet=Alice listunspent 1 | jq '.[0]')
BOB_UTXO=$(btc   -rpcwallet=Bob   listunspent 1 | jq '.[0]')

ALICE_TXID=$(echo "$ALICE_UTXO" | jq -r '.txid')
ALICE_VOUT=$(echo "$ALICE_UTXO" | jq    '.vout')
ALICE_AMT=$(echo  "$ALICE_UTXO" | jq -r '.amount')

BOB_TXID=$(echo   "$BOB_UTXO"   | jq -r '.txid')
BOB_VOUT=$(echo   "$BOB_UTXO"   | jq    '.vout')
BOB_AMT=$(echo    "$BOB_UTXO"   | jq -r '.amount')

echo "Alice UTXO: $ALICE_TXID:$ALICE_VOUT ($ALICE_AMT BTC)"
echo "Bob   UTXO: $BOB_TXID:$BOB_VOUT ($BOB_AMT BTC)"

# Change addresses
ALICE_CHANGE_ADDR=$(btc -rpcwallet=Alice getnewaddress "Change")
BOB_CHANGE_ADDR=$(btc   -rpcwallet=Bob   getnewaddress "Change")

# Each contributes exactly 10 BTC; fee split equally (0.0001 each)
FEE="0.0001"
ALICE_CONTRIBUTION="10"
BOB_CONTRIBUTION="10"

ALICE_CHANGE=$(echo "$ALICE_AMT $ALICE_CONTRIBUTION $FEE" | LC_ALL=C awk '{printf "%.8f", $1 - $2 - $3}')
BOB_CHANGE=$(echo   "$BOB_AMT   $BOB_CONTRIBUTION   $FEE" | LC_ALL=C awk '{printf "%.8f", $1 - $2 - $3}')

echo "Alice change: $ALICE_CHANGE BTC"
echo "Bob   change: $BOB_CHANGE BTC"
echo "Multisig receives: 20 BTC"

# Create the base PSBT (unsigned, two inputs)
FUNDING_PSBT=$(btc createpsbt \
    "[{\"txid\":\"$ALICE_TXID\",\"vout\":$ALICE_VOUT},{\"txid\":\"$BOB_TXID\",\"vout\":$BOB_VOUT}]" \
    "{\"$MULTISIG_ADDR\":20,\"$ALICE_CHANGE_ADDR\":$ALICE_CHANGE,\"$BOB_CHANGE_ADDR\":$BOB_CHANGE}")

echo "Funding PSBT created."

# Alice and Bob each sign their own input independently (parallel, LBTCL §7.2)
PSBT_SIGNED_ALICE=$(btc -rpcwallet=Alice walletprocesspsbt "$FUNDING_PSBT" | jq -r '.psbt')
echo "Alice signed funding PSBT."

PSBT_SIGNED_BOB=$(btc -rpcwallet=Bob walletprocesspsbt "$FUNDING_PSBT" | jq -r '.psbt')
echo "Bob signed funding PSBT."

# Combine both partial signatures → one fully-signed PSBT
COMBINED_FUNDING=$(btc combinepsbt "[\"$PSBT_SIGNED_ALICE\",\"$PSBT_SIGNED_BOB\"]")
echo "Funding PSBTs combined."

ANALYZE=$(btc analyzepsbt "$COMBINED_FUNDING")
echo "PSBT analysis: $(echo "$ANALYZE" | jq '{next, estimated_feerate}')"

# Finalize and broadcast
FINAL_HEX=$(btc finalizepsbt "$COMBINED_FUNDING" | jq -r '.hex')
FUNDING_TXID=$(btc sendrawtransaction "$FINAL_HEX")
echo "Funding TX broadcast: $FUNDING_TXID"

# ==============================================================================
echo "--- Step 8 (5): Mine blocks to confirm funding ---"
btc generatetoaddress 6 "$MINER_ADDR" > /dev/null
echo "6 blocks mined."

# ==============================================================================
echo "--- Step 9 (6): Print balances after funding ---"
ALICE_BAL=$(btc -rpcwallet=Alice getbalance)
BOB_BAL=$(btc   -rpcwallet=Bob   getbalance)
MS_BAL=$(btc    -rpcwallet=Multisig getbalance)
echo "  Alice   : $ALICE_BAL BTC"
echo "  Bob     : $BOB_BAL BTC"
echo "  Multisig: $MS_BAL BTC"
echo ""

# ==============================================================================
# PARTE 2: SETTLE MULTISIG
# ==============================================================================

echo ""
echo "======================================================================"
echo "  SETTLE MULTISIG"
echo "======================================================================"

echo "--- Step 10 (1): Create PSBT to spend from Multisig → 3 BTC to Alice, rest to Bob ---"
# Locate the multisig UTXO using the Multisig watch-only wallet (it tracks it)
MULTISIG_UTXOS=$(btc -rpcwallet=Multisig listunspent 1)
MS_UTXO=$(echo "$MULTISIG_UTXOS" | jq '.[0]')
MS_TXID=$(echo "$MS_UTXO" | jq -r '.txid')
MS_VOUT=$(echo "$MS_UTXO" | jq    '.vout')
MS_AMT=$(echo  "$MS_UTXO" | jq -r '.amount')

echo "Multisig UTXO: $MS_TXID:$MS_VOUT ($MS_AMT BTC)"

# Recipient addresses
ALICE_RECEIVE_ADDR=$(btc -rpcwallet=Alice getnewaddress "From Multisig")
BOB_RECEIVE_ADDR=$(btc   -rpcwallet=Bob   getnewaddress "From Multisig")

# 3 BTC to Alice, rest to Bob minus fee
SETTLE_FEE="0.0002"
ALICE_RECEIVE="3"
BOB_RECEIVE=$(echo "$MS_AMT $ALICE_RECEIVE $SETTLE_FEE" | LC_ALL=C awk '{printf "%.8f", $1 - $2 - $3}')

echo "Alice receives: $ALICE_RECEIVE BTC"
echo "Bob   receives: $BOB_RECEIVE BTC"
echo "Fee: $SETTLE_FEE BTC"

# Create the spending PSBT
SETTLE_PSBT=$(btc createpsbt \
    "[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT}]" \
    "{\"$ALICE_RECEIVE_ADDR\":$ALICE_RECEIVE,\"$BOB_RECEIVE_ADDR\":$BOB_RECEIVE}")

echo "Settle PSBT created."

# Update the PSBT with the multisig descriptor so the signers' wallets 
# know the witnessScript and HD keypaths for the inputs.
SETTLE_PSBT=$(btc utxoupdatepsbt "$SETTLE_PSBT" "[\"$MULTISIG_DESC\"]")
echo "Settle PSBT updated with descriptor info."

# ==============================================================================
echo "--- Step 11 (2): Alice signs the Settle PSBT ---"
SETTLE_PSBT_ALICE=$(btc -rpcwallet=Alice walletprocesspsbt "$SETTLE_PSBT" | jq -r '.psbt')
echo "Alice signed."

# ==============================================================================
echo "--- Step 12 (3): Bob signs the Settle PSBT ---"
SETTLE_PSBT_BOB=$(btc -rpcwallet=Bob walletprocesspsbt "$SETTLE_PSBT" | jq -r '.psbt')
echo "Bob signed."

# ==============================================================================
echo "--- Step 13 (4): Combine both partial signatures, finalize and broadcast ---"
COMBINED_SETTLE=$(btc combinepsbt "[\"$SETTLE_PSBT_ALICE\",\"$SETTLE_PSBT_BOB\"]")
echo "PSBTs combined."

FINALIZED=$(btc finalizepsbt "$COMBINED_SETTLE")
IS_COMPLETE=$(echo "$FINALIZED" | jq -r '.complete')

if [ "$IS_COMPLETE" != "true" ]; then
    echo "ERROR: PSBT is not complete after combining. Aborting."
    echo "$(btc analyzepsbt "$COMBINED_SETTLE")"
    exit 1
fi

SETTLE_HEX=$(echo "$FINALIZED" | jq -r '.hex')
SETTLE_TXID=$(btc sendrawtransaction "$SETTLE_HEX")
echo "Settle TX broadcast: $SETTLE_TXID"

# Mine to confirm
btc generatetoaddress 6 "$MINER_ADDR" > /dev/null
echo "6 blocks mined."

# ==============================================================================
echo "--- Step 14 (5): Print final balances ---"
echo "FINAL BALANCES AFTER SETTLE:"
echo "  Alice   : $(btc -rpcwallet=Alice getbalance) BTC"
echo "  Bob     : $(btc -rpcwallet=Bob   getbalance) BTC"
echo "  Multisig: $(btc -rpcwallet=Multisig getbalance) BTC (should be 0)"
echo ""

btc stop > /dev/null
echo "Node stopped."
