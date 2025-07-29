#!/bin/bash
set -euo pipefail

BITCOIN_DATA_DIR="$HOME/.bitcoin"
MINER_WALLET="Miner"
ALICE_WALLET="Alice"
BOB_WALLET="Bob"
MULTISIG_WALLET="Multisig"

cleanup() {
    bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop 2>/dev/null || true
    sleep 2
}
trap cleanup EXIT

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

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MINER_WALLET" false false "" false true > /dev/null
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$ALICE_WALLET" false false "" false true > /dev/null
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$BOB_WALLET" false false "" false true > /dev/null

MINER_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" getnewaddress)
ALICE_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getnewaddress)
BOB_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" getnewaddress)

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 101 "$MINER_ADDR" > /dev/null

ALICE_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$ALICE_ADDR" 15)
BOB_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MINER_WALLET" sendtoaddress "$BOB_ADDR" 15)

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null

EXT_XPUB_ALICE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listdescriptors | jq -r '.descriptors[] | select(.desc | contains("/0/*") and startswith("wpkh")) | .desc' | grep -Po '(?<=\().*(?=\))')
EXT_XPUB_BOB=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listdescriptors | jq -r '.descriptors[] | select(.desc | contains("/0/*") and startswith("wpkh")) | .desc' | grep -Po '(?<=\().*(?=\))')

INT_XPUB_ALICE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listdescriptors | jq -r '.descriptors[] | select(.desc | contains("/1/*") and startswith("wpkh")) | .desc' | grep -Po '(?<=\().*(?=\))')
INT_XPUB_BOB=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listdescriptors | jq -r '.descriptors[] | select(.desc | contains("/1/*") and startswith("wpkh")) | .desc' | grep -Po '(?<=\().*(?=\))')

EXT_MULTISIG_DESC_RAW="wsh(multi(2,$EXT_XPUB_ALICE,$EXT_XPUB_BOB))"
INT_MULTISIG_DESC_RAW="wsh(multi(2,$INT_XPUB_ALICE,$INT_XPUB_BOB))"

EXT_MULTISIG_DESC=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getdescriptorinfo "$EXT_MULTISIG_DESC_RAW" | jq -r '.descriptor')
INT_MULTISIG_DESC=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getdescriptorinfo "$INT_MULTISIG_DESC_RAW" | jq -r '.descriptor')

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createwallet "$MULTISIG_WALLET" true true > /dev/null

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" importdescriptors \
  "[{\"desc\":\"$EXT_MULTISIG_DESC\",\"active\":true,\"internal\":false,\"timestamp\":0},{\"desc\":\"$INT_MULTISIG_DESC\",\"active\":true,\"internal\":true,\"timestamp\":0}]" > /dev/null

MULTISIG_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getnewaddress)
MULTISIG_DESC="$EXT_MULTISIG_DESC"

ALICE_UTXOS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" listunspent)
BOB_UTXOS=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" listunspent)

ALICE_TXID_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].txid')
ALICE_VOUT_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].vout')
ALICE_AMOUNT_INPUT=$(echo "$ALICE_UTXOS" | jq -r '.[0].amount')

BOB_TXID_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].txid')
BOB_VOUT_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].vout')
BOB_AMOUNT_INPUT=$(echo "$BOB_UTXOS" | jq -r '.[0].amount')

ALICE_CHANGE=$(echo "$ALICE_AMOUNT_INPUT - 10 - 0.001" | bc -l)
BOB_CHANGE=$(echo "$BOB_AMOUNT_INPUT - 10 - 0.001" | bc -l)

FUNDING_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" createpsbt \
  "[{\"txid\":\"$ALICE_TXID_INPUT\",\"vout\":$ALICE_VOUT_INPUT},{\"txid\":\"$BOB_TXID_INPUT\",\"vout\":$BOB_VOUT_INPUT}]" \
  "{\"$MULTISIG_ADDR\":20,\"$ALICE_ADDR\":$ALICE_CHANGE,\"$BOB_ADDR\":$BOB_CHANGE}")

ALICE_SIGNED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" walletprocesspsbt "$FUNDING_PSBT" | jq -r '.psbt')
BOB_SIGNED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" walletprocesspsbt "$ALICE_SIGNED_PSBT" | jq -r '.psbt')

FINAL_TX=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" finalizepsbt "$BOB_SIGNED_PSBT" | jq -r '.hex')
FUNDING_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$FINAL_TX")

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" rescanblockchain 0 > /dev/null

ALICE_BALANCE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getbalances | jq -r '.mine.trusted')
BOB_BALANCE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" getbalances | jq -r '.mine.trusted')
MULTISIG_BALANCE=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getbalances | jq -r '.mine.trusted')

echo "Saldos después del financiamiento:"
echo "Alice: $ALICE_BALANCE BTC"
echo "Bob: $BOB_BALANCE BTC"
echo "Multisig: $MULTISIG_BALANCE BTC"

MULTI_UTXO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" listunspent | jq '.[0]')
MS_TXID=$(echo "$MULTI_UTXO" | jq -r '.txid')
MS_VOUT=$(echo "$MULTI_UTXO" | jq -r '.vout')
MS_AMOUNT=$(echo "$MULTI_UTXO" | jq -r '.amount')

if [ "$MS_TXID" = "null" ] || [ -z "$MS_TXID" ]; then
    TX_INFO=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" getrawtransaction "$FUNDING_TXID" true)
    MS_VOUT=$(echo "$TX_INFO" | jq -r '.vout[] | select(.scriptPubKey.address == "'$MULTISIG_ADDR'") | .n')
    MS_AMOUNT=$(echo "$TX_INFO" | jq -r '.vout[] | select(.scriptPubKey.address == "'$MULTISIG_ADDR'") | .value')
    MS_TXID="$FUNDING_TXID"
fi

MULTISIG_CHANGE_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getnewaddress)
ALICE_NEW_ADDR=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getnewaddress "Desde Multisig")

LIQUIDATION_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" walletcreatefundedpsbt \
  "[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT}]" \
  "{\"$ALICE_NEW_ADDR\":3,\"$MULTISIG_CHANGE_ADDR\":16.9999}" \
  0 '{"includeWatching":true}' | jq -r '.psbt')

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" importdescriptors \
  "[{\"desc\":\"$MULTISIG_DESC\",\"active\":false,\"internal\":false,\"timestamp\":0}]" > /dev/null 2>&1 || true

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" importdescriptors \
  "[{\"desc\":\"$MULTISIG_DESC\",\"active\":false,\"internal\":false,\"timestamp\":0}]" > /dev/null 2>&1 || true

ALICE_LIQUID_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" walletprocesspsbt "$LIQUIDATION_PSBT")
ALICE_LIQUID_PSBT=$(echo "$ALICE_LIQUID_RESULT" | jq -r '.psbt')

BOB_LIQUID_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" walletprocesspsbt "$LIQUIDATION_PSBT")
BOB_LIQUID_PSBT=$(echo "$BOB_LIQUID_RESULT" | jq -r '.psbt')

COMBINED_PSBT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" combinepsbt "[\"$ALICE_LIQUID_PSBT\",\"$BOB_LIQUID_PSBT\"]")

FINAL_RESULT=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" finalizepsbt "$COMBINED_PSBT")
PSBT_COMPLETE=$(echo "$FINAL_RESULT" | jq -r '.complete')

if [ "$PSBT_COMPLETE" = "true" ]; then
    FINAL_LIQUID_TX=$(echo "$FINAL_RESULT" | jq -r '.hex')
else
    echo "Error: No se pudo completar la PSBT"
    exit 1
fi

LIQUIDATION_TXID=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" sendrawtransaction "$FINAL_LIQUID_TX")
bitcoin-cli -datadir="$BITCOIN_DATA_DIR" generatetoaddress 3 "$MINER_ADDR" > /dev/null

ALICE_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$ALICE_WALLET" getbalances | jq -r '.mine.trusted')
BOB_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$BOB_WALLET" getbalances | jq -r '.mine.trusted')
MULTISIG_FINAL=$(bitcoin-cli -datadir="$BITCOIN_DATA_DIR" -rpcwallet="$MULTISIG_WALLET" getbalances | jq -r '.mine.trusted')

echo "Saldos finales:"
echo "Alice: $ALICE_FINAL BTC"
echo "Bob: $BOB_FINAL BTC"
echo "Multisig: $MULTISIG_FINAL BTC"

bitcoin-cli -datadir="$BITCOIN_DATA_DIR" stop
