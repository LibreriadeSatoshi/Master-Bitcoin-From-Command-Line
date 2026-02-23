#!/bin/bash

# ============================================================
# Exercise 1 - Master Bitcoin from the Command Line
# ============================================================

BITCOIN_VERSION="28.1"
BITCOIN_DIST="bitcoin-${BITCOIN_VERSION}-arm64-apple-darwin"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/${BITCOIN_DIST}.tar.gz"
SHA256SUMS_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
DATA_DIR="$HOME/.bitcoin"
BIN_DIR="$(pwd)/bitcoin-${BITCOIN_VERSION}/bin"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================
# SETUP
# ============================================================

# 1. Download
echo "Downloading Bitcoin Core ${BITCOIN_VERSION}..."
if [ ! -f "${BITCOIN_DIST}.tar.gz" ]; then
    curl -O "${BITCOIN_URL}"
else
    echo "File already exists, skipping download."
fi

# 2. Verify
echo "Verifying signature..."
[ ! -f "SHA256SUMS" ] && curl -O "${SHA256SUMS_URL}"

EXPECTED_HASH=$(grep "${BITCOIN_DIST}.tar.gz" SHA256SUMS | awk '{print $1}')
CALCULATED_HASH=$(shasum -a 256 "${BITCOIN_DIST}.tar.gz" | awk '{print $1}')

if [ "$EXPECTED_HASH" == "$CALCULATED_HASH" ]; then
    echo "Binary signature verification successful"
else
    echo -e "${RED}Verification failed!${NC}"
    exit 1
fi

# 3. Extract
echo "Extracting..."
if [ ! -d "bitcoin-${BITCOIN_VERSION}" ]; then
    tar -xf "${BITCOIN_DIST}.tar.gz"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        xattr -r -d com.apple.quarantine "bitcoin-${BITCOIN_VERSION}" || true
        find "bitcoin-${BITCOIN_VERSION}/bin" -type f -perm +111 -exec codesign -s - --force {} \; || true
    fi
else
    echo "Directory already exists, skipping extraction."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        xattr -r -d com.apple.quarantine "bitcoin-${BITCOIN_VERSION}" || true
        find "bitcoin-${BITCOIN_VERSION}/bin" -type f -perm +111 -exec codesign -s - --force {} \; || true
    fi
fi

# 3. Copy binaries to /usr/local/bin
echo "Copying binaries to /usr/local/bin..."
sudo cp "${BIN_DIR}/bitcoin-cli" /usr/local/bin/
sudo cp "${BIN_DIR}/bitcoind" /usr/local/bin/
echo "Binaries installed."

CMD_CLI="${BIN_DIR}/bitcoin-cli -datadir=${DATA_DIR}"
CMD_DAEMON="${BIN_DIR}/bitcoind -datadir=${DATA_DIR}"

# ============================================================
# INITIATE
# ============================================================

# 1. Create bitcoin.conf
mkdir -p "$DATA_DIR"
echo "Creating bitcoin.conf..."
cat <<EOF > "$DATA_DIR/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=user
rpcpassword=pass
EOF

# 2. Start bitcoind
echo "Starting bitcoind..."
if ! $CMD_DAEMON -daemon 2>/dev/null; then
    echo "bitcoind already running, continuing..."
fi
sleep 5

# 3. Create wallets
echo "Creating wallets..."
$CMD_CLI -regtest createwallet "Miner"  2>/dev/null || true
$CMD_CLI -regtest createwallet "Trader" 2>/dev/null || true

# 4. Generate address for Miner
MINER_ADDR=$($CMD_CLI -regtest -rpcwallet=Miner getnewaddress "Mining Reward")

# 5. Mine blocks until positive balance
# Bitcoin requires coinbase outputs to have 100 confirmations (coinbase maturity)
# before they can be spent. Mining 101 blocks makes the first reward spendable.
echo "Mining blocks..."
$CMD_CLI -regtest -rpcwallet=Miner generatetoaddress 101 "$MINER_ADDR" > /dev/null
echo "Mined 101 blocks to reach positive balance (coinbase maturity requires 100 confirmations)."

# 7. Print Miner balance
MINER_BALANCE=$($CMD_CLI -regtest -rpcwallet=Miner getbalance)
echo -e "Miner Balance: ${GREEN}${MINER_BALANCE} BTC${NC}"

# ============================================================
# USAGE
# ============================================================

# 1. Create Trader receiving address
TRADER_ADDR=$($CMD_CLI -regtest -rpcwallet=Trader getnewaddress "Received")

# 2. Send 20 BTC from Miner to Trader
$CMD_CLI -regtest -rpcwallet=Miner settxfee 0.0002
echo "Sending 20 BTC to Trader..."
TX_ID=$($CMD_CLI -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)
echo "TXID: $TX_ID"

# 3. Fetch from mempool and print
echo ""
echo "Unconfirmed transaction in mempool:"
$CMD_CLI -regtest getmempoolentry "$TX_ID" | jq .

# 4. Confirm with 1 block
$CMD_CLI -regtest -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" > /dev/null
echo "Transaction confirmed."

# 5. Fetch and print transaction details
RAW_TX=$($CMD_CLI -regtest getrawtransaction "$TX_ID")
DECODED=$($CMD_CLI -regtest decoderawtransaction "$RAW_TX")
TX_DETAIL=$($CMD_CLI -regtest -rpcwallet=Miner gettransaction "$TX_ID" true true)

BLOCK_HASH=$(echo "$TX_DETAIL" | jq -r '.blockhash')
BLOCK_HEIGHT=$($CMD_CLI -regtest getblock "$BLOCK_HASH" | jq -r '.height')

FEE=$(echo "$TX_DETAIL" | jq -r '.fee')
FEE_POSITIVE="${FEE#-}"

INPUT_TXID=$(echo "$DECODED" | jq -r '.vin[0].txid')
INPUT_VOUT=$(echo "$DECODED" | jq -r '.vin[0].vout')
INPUT_TX=$($CMD_CLI -regtest getrawtransaction "$INPUT_TXID" true)
INPUT_ADDR=$(echo "$INPUT_TX" | jq -r --argjson vout "$INPUT_VOUT" '.vout[$vout].scriptPubKey.address')
INPUT_AMOUNT=$(echo "$INPUT_TX" | jq -r --argjson vout "$INPUT_VOUT" '.vout[$vout].value')

SEND_OUTPUT=$(echo "$DECODED" | jq -r --arg addr "$TRADER_ADDR" '.vout[] | select(.scriptPubKey.address == $addr)')
SEND_AMOUNT=$(echo "$SEND_OUTPUT" | jq -r '.value')

CHANGE_OUTPUT=$(echo "$DECODED" | jq -r --arg addr "$TRADER_ADDR" '.vout[] | select(.scriptPubKey.address != $addr) | select(.value != 0)')
CHANGE_ADDR=$(echo "$CHANGE_OUTPUT" | jq -r '.scriptPubKey.address')
CHANGE_AMOUNT=$(echo "$CHANGE_OUTPUT" | jq -r '.value')

MINER_FINAL=$($CMD_CLI -regtest -rpcwallet=Miner getbalance)
TRADER_FINAL=$($CMD_CLI -regtest -rpcwallet=Trader getbalance)

echo ""
echo "--- Transaction Details ---"
echo "txid:              $TX_ID"
echo "From, Amount:      $INPUT_ADDR, $INPUT_AMOUNT BTC"
echo "Send, Amount:      $TRADER_ADDR, $SEND_AMOUNT BTC"
echo "Change, Amount:    $CHANGE_ADDR, $CHANGE_AMOUNT BTC"
echo "Fees:              $FEE_POSITIVE BTC"
echo "Block:             $BLOCK_HEIGHT"
echo "Miner Balance:     $MINER_FINAL BTC"
echo "Trader Balance:    $TRADER_FINAL BTC"
echo "--------------------------"
echo -e "${GREEN}Exercise 1 Completed!${NC}"
