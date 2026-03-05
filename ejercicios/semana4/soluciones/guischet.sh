#!/bin/bash

# Exit on error
set -e

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
    wget -q "${BASE_URL}/${FILENAME}"
    wget -q "${BASE_URL}/SHA256SUMS"
    wget -q "${BASE_URL}/SHA256SUMS.asc"
fi

sha256sum --ignore-missing --check SHA256SUMS > /dev/null
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

bitcoind -datadir="$DATA_DIR" -daemon > /dev/null
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

echo ""
echo "======================================================================"
echo "  SETUP TIMELOCK CONTRACT (Absolute)"
echo "======================================================================"

echo "--- 1. Create Wallets: Miner, Employee, Employer ---"
btc createwallet "Miner" > /dev/null
btc createwallet "Employee" > /dev/null
btc createwallet "Employer" > /dev/null
echo "Wallets created."

echo "--- 2. Fund the wallets ---"
MINER_ADDR=$(btc -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining 103 blocks to fund Miner..."
btc generatetoaddress 103 "$MINER_ADDR" > /dev/null
echo "Miner balance: $(btc -rpcwallet=Miner getbalance) BTC"

EMPLOYER_ADDR=$(btc -rpcwallet=Employer getnewaddress "Funds")
echo "Sending 50 BTC from Miner to Employer..."
btc -rpcwallet=Miner sendtoaddress "$EMPLOYER_ADDR" 50 > /dev/null
btc generatetoaddress 6 "$MINER_ADDR" > /dev/null
echo "Employer balance: $(btc -rpcwallet=Employer getbalance) BTC"
echo "Employee balance: $(btc -rpcwallet=Employee getbalance) BTC"

echo "--- 3. Create a salary transaction of 40 BTC (Employer -> Employee) ---"
EMPLOYEE_ADDR=$(btc -rpcwallet=Employee getnewaddress "Salary")

EMPLOYER_UTXO=$(btc -rpcwallet=Employer listunspent 1 | jq '.[0]')
TXID=$(echo "$EMPLOYER_UTXO" | jq -r '.txid')
VOUT=$(echo "$EMPLOYER_UTXO" | jq '.vout')
AMOUNT=$(echo "$EMPLOYER_UTXO" | jq -r '.amount')

# Calculate change
FEE="0.0001"
PAYMENT="40"
CHANGE=$(echo "$AMOUNT $PAYMENT $FEE" | LC_ALL=C awk '{printf "%.8f", $1 - $2 - $3}')
EMPLOYER_CHANGE_ADDR=$(btc -rpcwallet=Employer getnewaddress "Change")

echo "--- 4. Add absolute timelock of 500 Blocks ---"
# Absolute timelock 500 blocks
# Use locktime=500 and sequence=4294967294 (0xfffffffe) for locktime to be active
RAW_TX=$(btc -rpcwallet=Employer createrawtransaction \
    "[{\"txid\":\"$TXID\",\"vout\":$VOUT,\"sequence\":4294967294}]" \
    "{\"$EMPLOYEE_ADDR\":$PAYMENT, \"$EMPLOYER_CHANGE_ADDR\":$CHANGE}" \
    500)

SIGNED_TX=$(btc -rpcwallet=Employer signrawtransactionwithwallet "$RAW_TX" | jq -r '.hex')
echo "Raw transaction created and signed."

echo "--- 5. Report what happens when trying to broadcast ---"
set +e
ERROR_MSG=$(btc sendrawtransaction "$SIGNED_TX" 2>&1)
set -e
echo "Expected failure when broadcasting before block 500:"
echo "-> $ERROR_MSG"

echo "--- 6. Mine up to 500th block and broadcast the transaction ---"
CURRENT_BLOCK=$(btc getblockcount)
BLOCKS_TO_MINE=$((500 - CURRENT_BLOCK))
echo "Mining $BLOCKS_TO_MINE blocks to reach block 500..."
btc generatetoaddress "$BLOCKS_TO_MINE" "$MINER_ADDR" > /dev/null

echo "Broadcasting transaction..."
TXID_SALARY=$(btc sendrawtransaction "$SIGNED_TX")
echo "Transaction broadcasted: $TXID_SALARY"

# Mine 1 block to confirm
btc generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "--- 7. Print final balances of Employee and Employer ---"
echo "Employer balance: $(btc -rpcwallet=Employer getbalance) BTC"
echo "Employee balance: $(btc -rpcwallet=Employee getbalance) BTC"

echo ""
echo "======================================================================"
echo "  SPEND FROM THE TIMELOCK (OP_RETURN)"
echo "======================================================================"

echo "--- 1. Create a spending transaction (Employee to new Employee address) ---"
EMPLOYEE_NEW_ADDR=$(btc -rpcwallet=Employee getnewaddress "NewWallet")
DATA_STR="I got my salary, I am rich"
DATA_HEX=$(echo -n "$DATA_STR" | xxd -p | tr -d '\n')

EMPLOYEE_UTXO=$(btc -rpcwallet=Employee listunspent 1 | jq '.[0]')
EMP_TXID=$(echo "$EMPLOYEE_UTXO" | jq -r '.txid')
EMP_VOUT=$(echo "$EMPLOYEE_UTXO" | jq '.vout')
EMP_AMOUNT=$(echo "$EMPLOYEE_UTXO" | jq -r '.amount')

EMP_FEE="0.0001"
EMP_NEW_AMOUNT=$(echo "$EMP_AMOUNT $EMP_FEE" | LC_ALL=C awk '{printf "%.8f", $1 - $2}')

echo "--- 2. Add an OP_RETURN output with string: '$DATA_STR' ---"
RAW_SPEND_TX=$(btc -rpcwallet=Employee createrawtransaction \
    "[{\"txid\":\"$EMP_TXID\",\"vout\":$EMP_VOUT}]" \
    "{\"$EMPLOYEE_NEW_ADDR\":$EMP_NEW_AMOUNT, \"data\":\"$DATA_HEX\"}")

echo "--- 3. Extract and broadcast the fully signed transaction ---"
SIGNED_SPEND_TX=$(btc -rpcwallet=Employee signrawtransactionwithwallet "$RAW_SPEND_TX" | jq -r '.hex')
SPEND_TXID=$(btc sendrawtransaction "$SIGNED_SPEND_TX")
echo "Spend TX broadcast: $SPEND_TXID"

btc generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "--- 4. Print the final balances of the Employee and Employer ---"
echo "Employer balance: $(btc -rpcwallet=Employer getbalance) BTC"
echo "Employee balance: $(btc -rpcwallet=Employee getbalance) BTC"

echo ""
echo "======================================================================"
echo "  SETUP A RELATIVE TIMELOCK"
echo "======================================================================"

echo "--- 1. Create a transaction (Employer pays 1 BTC to Miner, relative timelock 10 blocks) ---"
# We need an unspent output from employer that is relatively new.
# The change from the 40 BTC transaction was confirmed 2 blocks ago.
EMPLOYER_UTXO2=$(btc -rpcwallet=Employer listunspent 1 | jq '.[0]')
TXID2=$(echo "$EMPLOYER_UTXO2" | jq -r '.txid')
VOUT2=$(echo "$EMPLOYER_UTXO2" | jq '.vout')
AMOUNT2=$(echo "$EMPLOYER_UTXO2" | jq -r '.amount')

PAY2="1.0"
FEE2="0.0001"
CHANGE2=$(echo "$AMOUNT2 $PAY2 $FEE2" | LC_ALL=C awk '{printf "%.8f", $1 - $2 - $3}')
MINER_PAY_ADDR=$(btc -rpcwallet=Miner getnewaddress "From Employer")
EMPLOYER_CHANGE2_ADDR=$(btc -rpcwallet=Employer getnewaddress "Change")

# Relative timelock 10 blocks: sequence=10
RAW_REL_TX=$(btc -rpcwallet=Employer createrawtransaction \
    "[{\"txid\":\"$TXID2\",\"vout\":$VOUT2,\"sequence\":10}]" \
    "{\"$MINER_PAY_ADDR\":$PAY2, \"$EMPLOYER_CHANGE2_ADDR\":$CHANGE2}")

SIGNED_REL_TX=$(btc -rpcwallet=Employer signrawtransactionwithwallet "$RAW_REL_TX" | jq -r '.hex')
echo "Transaction created and signed with sequence=10"

echo "--- 2. Report what happens when trying to broadcast ---"
set +e
ERROR_MSG_REL=$(btc sendrawtransaction "$SIGNED_REL_TX" 2>&1)
set -e
echo "Expected failure:"
echo "-> $ERROR_MSG_REL"

echo ""
echo "======================================================================"
echo "  SPEND FROM THE RELATIVE TIMELOCK"
echo "======================================================================"

echo "--- 1. Generate 10 blocks ---"
btc generatetoaddress 10 "$MINER_ADDR" > /dev/null

echo "--- 2. Broadcast the second transaction. Confirm generating one more block ---"
TXID_REL=$(btc sendrawtransaction "$SIGNED_REL_TX")
echo "Transaction broadcasted successfully: $TXID_REL"

btc generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "--- 3. Report Employer balance ---"
echo "Final Employer balance: $(btc -rpcwallet=Employer getbalance) BTC"

echo ""
echo "Cleaning up..."
btc stop > /dev/null
echo "Node stopped."
