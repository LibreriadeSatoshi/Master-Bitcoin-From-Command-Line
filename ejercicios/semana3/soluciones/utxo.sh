#!/bin/bash

# Create three wallets: Miner, Alice, and Bob.
bitcoin-cli createwallet Miner
bitcoin-cli createwallet Alice
bitcoin-cli createwallet Bob


# Fund the wallets by generating some blocks for Miner
MINER_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining reward")
bitcoin-cli generatetoaddress 103 "$MINER_ADDR"


# Send 50 coins to both Alice and Bob
ALICE_ADDR=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Funding")
BOB_ADDR=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Funding")

TXID=$(bitcoin-cli -rpcwallet=Miner send "[{\"$ALICE_ADDR\": 50}, {\"$BOB_ADDR\": 50}]" | jq -r '.txid')


# Mine one more block to Miner so balances are updated
bitcoin-cli generatetoaddress 1 "$MINER_ADDR"


# Create a 2-of-2 Multisig address by combining public keys from Alice and Bob.
EXT_XPUB_ALICE=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
EXT_XPUB_BOB=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')

INT_XPUB_ALICE=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
INT_XPUB_BOB=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')

EXT_DESC="wsh(multi(2,$EXT_XPUB_ALICE,$EXT_XPUB_BOB))"
INT_DESC="wsh(multi(2,$INT_XPUB_ALICE,$INT_XPUB_BOB))"

EXT_DESC_SUM=$(bitcoin-cli getdescriptorinfo $EXT_DESC | jq '.descriptor')
INT_DESC_SUM=$(bitcoin-cli getdescriptorinfo $INT_DESC | jq '.descriptor')

MULTI_EXT_DESC="{\"desc\": $EXT_DESC_SUM, \"active\": true, \"internal\": false, \"timestamp\": \"now\"}"
MULTI_INT_DESC="{\"desc\": $INT_DESC_SUM, \"active\": true, \"internal\": true, \"timestamp\": \"now\"}"

MULTI_DESC="[$MULTI_EXT_DESC, $MULTI_INT_DESC]"

bitcoin-cli -named createwallet wallet_name="Multisig" disable_private_keys=true blank=true
bitcoin-cli -rpcwallet="Multisig" importdescriptors "$MULTI_DESC"
bitcoin-cli -rpcwallet="Multisig" getwalletinfo

MULTI_ADDR=$(bitcoin-cli -rpcwallet="Multisig" getnewaddress)
echo "Multisig address: $MULTI_ADDR"
echo "Multisig balance: $(bitcoin-cli -rpcwallet="Multisig" getbalances | jq -r '.mine.trusted')"
bitcoin-cli -rpcwallet="Multisig" getbalances


# Create a Partially Signed Bitcoin Transaction (PSBT) to fund the multisig address with 20 BTC, taking 10 BTC each from Alice and Bob, and providing correct change back to each of them.
ALICE_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Change")
BOB_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Change")

ALICE_UTXO_TXID=$(bitcoin-cli -rpcwallet=Alice listunspent | jq -r '.[0].txid')
ALICE_UTXO_VOUT=$(bitcoin-cli -rpcwallet=Alice listunspent | jq -r '.[0].vout')
echo $ALICE_UTXO_TXID $ALICE_UTXO_VOUT

BOB_UTXO_TXID=$(bitcoin-cli -rpcwallet=Bob listunspent | jq -r '.[0].txid')
BOB_UTXO_VOUT=$(bitcoin-cli -rpcwallet=Bob listunspent | jq -r '.[0].vout')
echo $BOB_UTXO_TXID $BOB_UTXO_VOUT

PSBT=$(bitcoin-cli -named createpsbt \
  inputs="[{\"txid\":\"$ALICE_UTXO_TXID\",\"vout\":$ALICE_UTXO_VOUT},{\"txid\":\"$BOB_UTXO_TXID\",\"vout\":$BOB_UTXO_VOUT}]" \
  outputs="[{\"$MULTI_ADDR\":20}, {\"$ALICE_CHANGE_ADDR\":39.9999}, {\"$BOB_CHANGE_ADDR\":39.9999}]")

PSBT_ALICE=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $PSBT | jq -r '.psbt')
bitcoin-cli -named analyzepsbt psbt=$PSBT_ALICE

PSBT_BOB=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $PSBT | jq -r '.psbt')
bitcoin-cli -named analyzepsbt psbt=$PSBT_BOB


# da igual si se firman por separado y se combian o si Alice firma uno y luego Bob firma el resultado de Alice.
PSBT_ALICE_AND_BOB=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $PSBT_ALICE | jq -r '.psbt')
bitcoin-cli -named analyzepsbt psbt=$PSBT_ALICE_AND_BOB

PSBT_COMBINED=$(bitcoin-cli combinepsbt "[\"$PSBT_ALICE\", \"$PSBT_BOB\"]")

if [ "$PSBT_ALICE_AND_BOB" = "$PSBT_COMBINED" ]; then
    echo "✅ Las PSBTs combinadas son idénticas"
else
    echo "⚠️ Las PSBTs combinadas son distintas"
fi


# finalize and send 
PSBT_HEX=$(bitcoin-cli finalizepsbt $PSBT_COMBINED | jq -r ".hex")
TXID=$(bitcoin-cli -named sendrawtransaction hexstring=$PSBT_HEX)

bitcoin-cli generatetoaddress 1 "$MINER_ADDR"
echo "Multisig balance: $(bitcoin-cli -rpcwallet="Multisig" getbalances | jq -r '.mine.trusted')"


# Crear un watch-only wallet para la multisig e importar el descriptor
bitcoin-cli -named createwallet wallet_name="watchonly-multisig" disable_private_keys=true blank=true
MULTI_DESC=$(echo $MULTI | jq -r '.descriptor')
bitcoin-cli -rpcwallet=watchonly-multisig importdescriptors "[{ \"desc\": \"$MULTI_DESC\", \"timestamp\": \"now\", \"active\": false }]"


# Crear una PSBT para gastar fondos del wallet Multisig, enviando 3 BTC a Alice. Genera una direccion de cambio desde el wallet Multisig
MULTI_UTXO_TXID=$(bitcoin-cli -rpcwallet=Multisig listunspent | jq -r '.[0].txid')
MULTI_UTXO_VOUT=$(bitcoin-cli -rpcwallet=Multisig listunspent | jq -r '.[0].vout')

MULTI_CHANGE_DESC=$(bitcoin-cli -rpcwallet=Multisig listdescriptors | jq -r '.descriptors[] | select(.internal == true) | .desc')
MULTI_NEXT_INDEX=$(bitcoin-cli -rpcwallet=Multisig listdescriptors | jq -r '.descriptors[] | select(.internal == true) | .next_index')
MULTI_CHANGE_ADDR=$(bitcoin-cli deriveaddresses "$MULTI_CHANGE_DESC" "[$MULTI_NEXT_INDEX,$MULTI_NEXT_INDEX]" | jq -r '.[0]')

ALICE_NEW_ADDR=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Multi")

SPEND_PSBT=$(bitcoin-cli -rpcwallet=Multisig -named walletcreatefundedpsbt \
  inputs='[{"txid":"'"$MULTI_UTXO_TXID"'","vout":'"$MULTI_UTXO_VOUT"'}]' \
  outputs='{"'"$MULTI_CHANGE_ADDR"'":16.9999, "'"$ALICE_NEW_ADDR"'":3}' \
  options='{"includeWatching":true}' | jq -r '.psbt')

bitcoin-cli decodepsbt $SPEND_PSBT


# Alice signs the PSBT
SPEND_PSBT_ALICE=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $SPEND_PSBT | jq -r '.psbt')
bitcoin-cli -named analyzepsbt psbt=$SPEND_PSBT_ALICE


# Bob signs the PSBT
SPEND_PSBT_BOB=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $SPEND_PSBT | jq -r '.psbt')
bitcoin-cli -named analyzepsbt psbt=$SPEND_PSBT_BOB


# Combine PSBTs
SPEND_PSBT_COMBINED=$(bitcoin-cli combinepsbt "[\"$SPEND_PSBT_ALICE\", \"$SPEND_PSBT_BOB\"]")
echo $SPEND_PSBT_COMBINED
bitcoin-cli -named analyzepsbt psbt=$SPEND_PSBT_COMBINED


# Finalize PSBT and send it
SPEND_PSBT_FINALIZED=$(bitcoin-cli -rpcwallet=Multisig finalizepsbt "$SPEND_PSBT_COMBINED" | jq -r '.hex')
SPEND_TXID=$(bitcoin-cli -named sendrawtransaction hexstring=$SPEND_PSBT_FINALIZED)


# Mine 1 more block to make balances trusted
bitcoin-cli generatetoaddress 1 "$MINER_ADDR"


# Print balances on screen
echo "Multi balance: $(bitcoin-cli -rpcwallet=Multisig getbalances | jq -r '.mine.trusted')"
echo "Alice balance: $(bitcoin-cli -rpcwallet=Alice getbalances | jq -r '.mine.trusted')"
echo "Bob's balance: $(bitcoin-cli -rpcwallet=Bob getbalances | jq -r '.mine.trusted')"