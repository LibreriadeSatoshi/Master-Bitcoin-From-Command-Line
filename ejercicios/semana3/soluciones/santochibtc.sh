#!/bin/bash

export PATH="$PWD/bitcoin-30.2/bin:$PATH"
rm -rf ~/.bitcoin/regtest/ &> /dev/null
./bitcoin-30.2/bin/bitcoind -daemon
sleep 3

# 1. Crear tres monederos: `Miner`, `Alice` y `Bob`.
alias bitcoin-cli="bitcoin-30.2/bin/bitcoin-cli -regtest -rpcuser=usuario -rpcpassword=contraseña"
bitcoin-cli createwallet Miner &&> /dev/null
bitcoin-cli loadwallet Miner &> /dev/null
bitcoin-cli createwallet Alice &> /dev/null
bitcoin-cli loadwallet Alice &> /dev/null
bitcoin-cli createwallet Bob &> /dev/null
bitcoin-cli loadwallet Bob &> /dev/null

# 2. Fondear los monederos generando algunos bloques para `Miner` y enviando algunas monedas a `Alice` y `Bob`.
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "Dirección de Minería: $miner_address"
bitcoin-cli generatetoaddress 101 "$miner_address" &> /dev/null
alice_address=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Fondeo")
bob_address=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Fondeo")
bitcoin-cli -rpcwallet=Miner sendtoaddress "$alice_address" 20 &> /dev/null
bitcoin-cli -rpcwallet=Miner sendtoaddress "$bob_address" 20 &> /dev/null
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null    

# 3. Crear un wallet Multisig 2-de-2 combinando los descriptors de `Alice` y `Bob`
descAint=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descAext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descBint=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descBext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
extdesc="wsh(multi(2,$descAext,$descBext))"
intdesc="wsh(multi(2,$descAint,$descBint))"
extdescsum=$(bitcoin-cli getdescriptorinfo $extdesc | jq -r '.descriptor')
intdescsum=$(bitcoin-cli getdescriptorinfo $intdesc | jq -r '.descriptor')
#bitcoin-cli -named createwallet wallet_name="multi" disable_private_keys=true blank=true &> /dev/null
echo "create wallet"
bitcoin-cli -named createwallet wallet_name="multi"  disable_private_keys=true blank=true &> /dev/null
bitcoin-cli -rpcwallet=multi importdescriptors "[{\"desc\": \"$extdescsum\",  \"timestamp\": \"now\", \"active\": true, \"internal\": false, \"range\": [0,100]}, {\"desc\": \"$intdescsum\", \"timestamp\": \"now\", \"active\": true, \"internal\": true, \"range\": [0,100]}]"
echo "import descriptors"
#bitcoin-cli -rpcwallet=multi importdescriptors "[{\"desc\": \"$extdescsum\", \"timestamp\": \"now\", \"active\": true, \"range\": [0,100]}]"
multi_address=$(bitcoin-cli -rpcwallet=multi getnewaddress)
echo "Dirección Multisig: $multi_address"

# 4. Crear una Transacción Bitcoin Parcialmente Firmada (PSBT) para financiar la dirección multisig con 20 BTC, tomando 10 BTC de Alice y 10 BTC de Bob, y proporcionando el cambio correcto a cada uno de ellos.
alice_utxo=$(bitcoin-cli -rpcwallet=Alice listunspent | jq '.[0]')
alice_txid=$(echo "$alice_utxo" | jq -r '.txid')
alice_vout=$(echo "$alice_utxo" | jq -r '.vout')
alice_amount=$(echo "$alice_utxo" | jq -r '.amount')
alice_change_address=$(bitcoin-cli -rpcwallet=Alice getrawchangeaddress)
alice_amount_change=$(echo "$alice_amount - 10 - 0.00001" | bc)

bob_utxo=$(bitcoin-cli -rpcwallet=Bob listunspent | jq '.[0]')
bob_txid=$(echo "$bob_utxo" | jq -r '.txid')
bob_vout=$(echo "$bob_utxo" | jq -r '.vout')
bob_amount=$(echo "$bob_utxo" | jq -r '.amount')
bob_change_address=$(bitcoin-cli -rpcwallet=Bob getrawchangeaddress)
bob_amount_change=$(echo "$bob_amount - 10 - 0.00001" | bc)

inputs="[{\"txid\": \"$alice_txid\", \"vout\": $alice_vout}, {\"txid\": \"$bob_txid\", \"vout\": $bob_vout}]"
outputs="{\"$multi_address\": 20, \"$alice_change_address\": $alice_amount_change, \"$bob_change_address\": $bob_amount_change}"
psbt=$(bitcoin-cli -rpcwallet=Alice createpsbt "$inputs" "$outputs")

# firmar
alice_psbt=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbt" | jq -r '.psbt')
bob_psbt=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$alice_psbt" | jq -r '.psbt')
combined_psbt=$(bitcoin-cli combinepsbt "[\"$alice_psbt\",\"$bob_psbt\"]")
final_psbt=$(bitcoin-cli finalizepsbt "$combined_psbt" | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction "$final_psbt")

# 5. Confirmar el saldo mediante la minería de algunos bloques adicionales.
bitcoin-cli generatetoaddress 1 "$multi_address" &> /dev/null

# 6. Imprimir los saldos finales de `Alice` y `Bob`.
echo "Saldo de Alice: $(bitcoin-cli -rpcwallet=Alice getbalance)"
echo "Saldo de Bob: $(bitcoin-cli -rpcwallet=Bob getbalance)"
echo "Saldo de Multisig: $(bitcoin-cli -rpcwallet=multi getbalance)"

#### Liquidar Multisig
# 1. Crear una PSBT para gastar fondos del wallet `Multisig`, enviando 3 BTC a `Alice`.
multi_utxo=$(bitcoin-cli -rpcwallet=multi listunspent | jq '.[0]')
multi_txid=$(echo "$multi_utxo" | jq -r '.txid')
multi_vout=$(echo "$multi_utxo" | jq -r '.vout')
multi_amount=$(echo "$multi_utxo" | jq -r '.amount')
alice_address=$(bitcoin-cli -rpcwallet=Alice getnewaddress)
change_address=$(bitcoin-cli -rpcwallet=multi getrawchangeaddress)
change_amount=$(echo "$multi_amount - 3 - 0.00001" | bc)
inputs="[{\"txid\": \"$multi_txid\", \"vout\": $multi_vout}]"
outputs="[{\"$alice_address\": 3}, {\"$change_address\": $change_amount}]"
psbt=$(bitcoin-cli -rpcwallet=multi createpsbt "$inputs" "$outputs")
multi_psbt=$(bitcoin-cli -rpcwallet=multi walletprocesspsbt "$psbt" | jq -r '.psbt')
echo "PSBT creada para gasto: $multi_psbt"

# 2. Firmar la PSBT por `Alice`.
echo "Analizando PSBT en Alice..."
alice_psbt=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$multi_psbt" | jq -r '.psbt')
bitcoin-cli -rpcwallet=Alice analyzepsbt "$alice_psbt"
# 3. Firmar la PSBT por `Bob`.
bob_psbt=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$alice_psbt" | jq -r '.psbt')
echo "Analizando PSBT en Bob..."
bitcoin-cli -rpcwallet=Bob analyzepsbt "$bob_psbt"
# 4. Extraer y transmitir la transacción completamente firmada.
combined_psbt=$(bitcoin-cli combinepsbt "[\"$alice_psbt\",\"$bob_psbt\"]")
final_psbt=$(bitcoin-cli finalizepsbt "$combined_psbt" | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction "$final_psbt")
echo "Tx de gasto transmitida: $txid"

# 5. Imprimir los saldos finales de `Alice` y `Bob`.
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null
echo "Saldo final de Alice: $(bitcoin-cli -rpcwallet=Alice getbalance)"
echo "Saldo final de Bob: $(bitcoin-cli -rpcwallet=Bob getbalance)"
echo "Saldo final de Multisig: $(bitcoin-cli -rpcwallet=multi getbalance)"

bitcoin-cli stop