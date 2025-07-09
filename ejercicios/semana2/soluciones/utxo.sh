#!/bin/bash

# create wallets
bitcoin-cli createwallet Trader

bitcoin-cli createwallet Miner


# get miner address
MINER_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")


# mine 103 blocks to get 3 spendable utxos
bitcoin-cli generatetoaddress 103 "$MINER_ADDR"

bitcoin-cli -rpcwallet=Miner getbalance


# get unspent transactions for Miner
UNSPENT=$(bitcoin-cli -rpcwallet=Miner listunspent)


# get oldest utxo txid & vout
INPUT0=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[-1]')

TXID0=$(echo $INPUT0 | jq -r '.txid')
echo $TXID0

VOUT0=$(echo $INPUT0 | jq -r '.vout')
echo $VOUT0


# get second oldest utxo txid & vout
INPUT1=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[-2]')

TXID1=$(echo $INPUT1 | jq -r '.txid')
echo $TXID1

VOUT1=$(echo $INPUT1 | jq -r '.vout')
echo $VOUT1


# get trader address
TRADER_ADDR=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Parent")
echo $TRADER_ADDR


# get cambio miner address
MINER_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Change")
echo $MINER_CHANGE_ADDR


# create raw transaction with 2 inputs (50 + 50) and 2 outputs (70 + 29.99999 + FEE=0.00001)
RAWTXHEX=$(bitcoin-cli createrawtransaction '''[ { "txid": "'$TXID0'", "vout": '$VOUT0' }, { "txid": "'$TXID1'", "vout": '$VOUT1' } ]''' '''[ { "'$TRADER_ADDR'": 70 }, { "'$MINER_CHANGE_ADDR'": 29.99999 } ]''' 0 true)


# check decoded raw transaction is correct
bitcoin-cli decoderawtransaction $RAWTXHEX | jq


# sign raw transaction
SIGNED_TX=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $RAWTXHEX | jq -r '.hex')


# check decoded signed raw transaction is correct (should have added signatures to txinwitness)
bitcoin-cli decoderawtransaction $SIGNED_TX | jq -r '.vin[].txinwitness'


# send signed transaction
TXHASH=$(bitcoin-cli sendrawtransaction $SIGNED_TX)


# check that we have the new transactions in the list; category should be `send` 
bitcoin-cli -rpcwallet=Miner listtransactions | jq -r .[length-2:]


# get txid from mempool, should be the same as TXHASH
TXID=$(bitcoin-cli getrawmempool | jq -r '.[]')
echo $TXID


# get and decode the transaction
RAW=$(bitcoin-cli getrawtransaction "$TXID")
DECODED=$(bitcoin-cli decoderawtransaction "$RAW")


# get input details (parent transactions)
INPUTS=$(echo "$DECODED" | jq -r '.vin')
echo $INPUTS | jq


# build "input" array with txid and vout
INPUT_ARRAY=$(echo "$INPUTS" | jq '[.[] | {txid: .txid, vout: .vout}]')


# get output details
OUTPUTS=$(echo "$DECODED" | jq -r '.vout')
echo $OUTPUTS | jq


# build "output" array with script_pubkey and amount
OUTPUT_ARRAY=$(echo "$OUTPUTS" | jq '[.[] | {script_pubkey: .scriptPubKey, amount: .value}]')


# get fees
FEES=$(bitcoin-cli getmempoolinfo | jq -r '.total_fee')
echo $FEES

# get weight (in vbytes) from mempool; assuming weight / 4 is what is needed but not clear
WEIGHT=$(bitcoin-cli getmempoolentry "$TXID" | jq '.vsize')
echo $WEIGHT


# print JSON to terminal
JSON=$(jq -n \
  --argjson input "$INPUT_ARRAY" \
  --argjson output "$OUTPUT_ARRAY" \
  --arg fees "$FEES" \
  --arg weight "$WEIGHT" \
  '{
    input: $input,
    output: $output,
    Fees: ($fees | tonumber),
    Weight: ($weight | tonumber)
  }')
echo $JSON | jq


# create new miner address
MINER_NEW_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner_2")
echo $MINER_NEW_ADDR


# create a new transaction (Child) that spends the previous transaction (Parent) vout 1 (Miner Change)
RAWTXHEX2=$(bitcoin-cli createrawtransaction '''[ { "txid": "'$TXID'", "vout": 1 } ]''' '''[ { "'$MINER_NEW_ADDR'": 29.99998 } ]''' 0 true)


# check child decoded raw transaction is correct
bitcoin-cli decoderawtransaction $RAWTXHEX2 | jq


# sign child raw transaction
SIGNED_TX2=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $RAWTXHEX2 | jq -r '.hex')


# send signed transaction
TXHASH2=$(bitcoin-cli sendrawtransaction $SIGNED_TX2)


# get child raw transaction from mempool
bitcoin-cli getmempoolentry $TXHASH2 | jq


# bump parent transaction fees by manually creating a rawtransaction with 10k fees
RAWTXHEX3=$(bitcoin-cli createrawtransaction '''[ { "txid": "'$TXID0'", "vout": '$VOUT0' }, { "txid": "'$TXID1'", "vout": '$VOUT1' } ]''' '''[ { "'$TRADER_ADDR'": 70 }, { "'$MINER_CHANGE_ADDR'": 29.9999 } ]''' 0 true)


# check child decoded raw transaction is correct
bitcoin-cli decoderawtransaction $RAWTXHEX3 | jq


# sign child raw transaction
SIGNED_TX3=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $RAWTXHEX3 | jq -r '.hex')


# send signed transaction
TXHASH3=$(bitcoin-cli sendrawtransaction $SIGNED_TX3)


# explanation of what happened?
echo "La transacción Child usaba como input la salida de la transacción Parent inicial, con un fee de 1000 satoshis"
echo "Al reemplazar la transacción Parent con una con un fee mayor, 10000 satoshis, la transacción Parent inicial es eliminada del mempool"
echo "Como la transacción Child usaba un UTxO de la transacción Parent que ya no existe, es eliminada también del mempool"
echo "El mempool ahora solo tiene una sola transacción, la segunda transacción Parent con fee de 10000 satoshis"

MEMPOOLTXID=$(bitcoin-cli getrawmempool | jq -r '.[]')
MEMPOOLTX=$(bitcoin-cli -rpcwallet=Miner gettransaction $MEMPOOLTXID | jq)
