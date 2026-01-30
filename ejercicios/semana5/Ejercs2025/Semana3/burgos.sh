#!/bin/bash

echo "Iniciando"

#Reiniciando regtest con nuevas variables
bitcoin-cli stop
sleep 1
rm -R ~/.bitcoin/regtest/

bitcoind -daemon
sleep 3

#Crear billeteras
bitcoin-cli createwallet "Miner" > /dev/null
bitcoin-cli createwallet "Alice" > /dev/null
bitcoin-cli createwallet "Bob" > /dev/null

#Generar direcciones y fondear
miner_address=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
alice_address=$(bitcoin-cli -rpcwallet="Alice" getnewaddress "ahorros")
bob_address=$(bitcoin-cli -rpcwallet="Bob" getnewaddress "sueldo")

bitcoin-cli -rpcwallet=Miner generatetoaddress 103 $miner_address > /dev/null
bitcoin-cli -rpcwallet=Miner sendtoaddress $alice_address 40
bitcoin-cli -rpcwallet=Miner sendtoaddress $bob_address 20
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null

balance_miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
balance_alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo "Miner balace = " $balance_miner
echo "$alice_address Alice balance= " $balance_alice
echo "$bob_address Bob balance = " $balance_bob

#Obteniendo descriptores
int_desc_alice=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc')
int_desc_bob=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc')

ext_desc_alice=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc')
ext_desc_bob=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc')

#echo "Alice parent_desc $desc_alice"

#Obtener xpubs
int_alice_xpub=$(echo $int_desc_alice | grep -oP '(?<=\().*(?=\))')
int_bob_xpub=$(echo $int_desc_bob | grep -oP '(?<=\().*(?=\))')

ext_alice_xpub=$(echo $ext_desc_alice | grep -oP '(?<=\().*(?=\))')
ext_bob_xpub=$(echo $ext_desc_bob | grep -oP '(?<=\().*(?=\))')
#echo "Xpubs $alice_xpub"

#Creando el Multisig con multi
int_multi_desc="wsh(multi(2,$int_alice_xpub,$int_bob_xpub))"
ext_multi_desc="wsh(multi(2,$ext_alice_xpub,$ext_bob_xpub))"

#$echo "int_multi_desc $int_multi_desc"

int_desc_info=$(bitcoin-cli getdescriptorinfo "$int_multi_desc")
ext_desc_info=$(bitcoin-cli getdescriptorinfo "$ext_multi_desc")

#echo "desc_info $desc_info"

int_descriptor=$(echo "$int_desc_info" | jq -r .descriptor)
ext_descriptor=$(echo "$ext_desc_info" | jq -r .descriptor)

#echo "descriptor $ext_descriptor"


#Creando wallet Multisig
bitcoin-cli createwallet "Multisig" true true > /dev/null
#echo "Wallet creada"

bitcoin-cli -rpcwallet=Multisig importdescriptors "[{
  \"desc\":\"$ext_descriptor\",
  \"timestamp\":\"now\",
  \"active\":true,
  \"internal\":false},
  {
  \"desc\":\"$int_descriptor\",
  \"timestamp\":\"now\",
  \"active\":true,
  \"internal\":true}
  ]" > /dev/null


multi_address=$(bitcoin-cli -rpcwallet=Multisig getnewaddress)
#echo "Multisig Address: " $multi_address

unspent_alice=$(bitcoin-cli -rpcwallet=Alice listunspent)
unspent_bob=$(bitcoin-cli -rpcwallet=Bob listunspent)

#Utxo de Alice y Bob
txid_alice=$(echo "$unspent_alice" | jq -r '.[0].txid')
vout_alice=$(echo "$unspent_alice" | jq -r '.[0].vout')
txid_bob=$(echo "$unspent_bob" | jq -r '.[0].txid')
vout_bob=$(echo "$unspent_bob" | jq -r '.[0].vout')

#Direcciones de cambio para Alice y bob
changeaddress_alice=$(bitcoin-cli -rpcwallet=Alice getrawchangeaddress)
changeaddress_bob=$(bitcoin-cli -rpcwallet=Bob getrawchangeaddress)


#Crear PSBT
psbt=$(bitcoin-cli createpsbt "[{\"txid\":\"$txid_alice\",\"vout\":$vout_alice}, {\"txid\":\"$txid_bob\",\"vout\":$vout_bob}]" \
  "{\"$multi_address\":20, \"$changeaddress_alice\":29.9999, \"$changeaddress_bob\":9.9999}")

#Firmar PSBT con ambos
psbt=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbt" | jq -r '.psbt')
psbt=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$psbt" | jq -r '.psbt')

#Finalizar y transmitir
hex_psbt=$(bitcoin-cli finalizepsbt "$psbt" | jq -r '.hex')
bitcoin-cli sendrawtransaction $hex_psbt > /dev/null

#Minar un bloque adicional
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null

#Saldos de las billeteras
balance_multi=$(bitcoin-cli -rpcwallet=Multisig getbalance)
balance_alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo -e "\n\nAfter send btc to Multisig"
echo "Alice balace = " $balance_alice
echo "Bob balace= " $balance_bob
echo "Multi balace = " $balance_multi


#------Liquidar Multisig

#Direccion de cambio de la Multisig
changeaddress_multi=$(bitcoin-cli -rpcwallet=Multisig getrawchangeaddress)
#Utxo de la Multisig
unspent_multi=$(bitcoin-cli -rpcwallet=Multisig listunspent)
txid_multi=$(echo "$unspent_multi" | jq -r '.[0].txid')
vout_multi=$(echo "$unspent_multi" | jq -r '.[0].vout')

psbtFunded=$(bitcoin-cli -rpcwallet=Multisig walletcreatefundedpsbt "[{\"txid\":\"$txid_multi\",\"vout\":$vout_multi}]" \
  "{\"$alice_address\":3, \"$changeaddress_multi\":16.9999}" | jq -r '.psbt') 

#echo "psbtFunded:" $psbtFunded
#bitcoin-cli decodepsbt $psbtFunded
#bitcoin-cli analyzepsbt $psbtFunded

#Firmar por separado y combinar
#Firmar PSBT con ambos
psbtFunded_alice=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbtFunded" | jq -r '.psbt')
psbtFunded_bob=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$psbtFunded" | jq -r '.psbt')
psbtFunded_combined=$(bitcoin-cli combinepsbt "[\"$psbtFunded_bob\", \"$psbtFunded_alice\"]")

#Finalizar y transmitir
hex_psbt=$(bitcoin-cli finalizepsbt "$psbtFunded_combined" | jq -r '.hex')
bitcoin-cli sendrawtransaction $hex_psbt > /dev/null

#Minar un bloque adicional
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null

#Actualizar saldos de las billeteras
balance_multi=$(bitcoin-cli -rpcwallet=Multisig getbalance)
balance_alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo -e "\n\nAfter settle Multisig"
echo "Alice balace = " $balance_alice
echo "Bob balace= " $balance_bob
echo "Multi balace = " $balance_multi
