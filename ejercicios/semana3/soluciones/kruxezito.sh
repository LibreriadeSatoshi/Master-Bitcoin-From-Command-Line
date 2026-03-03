#!/bin/bash

#-----------COPIE MI INICIALIZACION DEL BITCOIND-----------

btr_cli="bitcoin-cli -conf=$HOME/.bitcoin/bitcoin.conf"

# Stop a Bitcoind para no tener problema al inicialiarlo.
$btr_cli stop &> /dev/null

sleep 3

# Remove a Regtest para Comenzar desde 0.
if [[ "$OSTYPE" == "darwin"* ]]; then
	rm -rf ~/Library/Application\ Support/Bitcoin/regtest
else
	rm -rf ~/.bitcoin/regtest/ &> /dev/null
fi

# Inicializando Bitcoind --daemon.
bitcoind -conf="$HOME/.bitcoin/bitcoin.conf" --daemon

sleep 5

# CONFIGURAR MULTISIG.

# 1- Crear 3 Wallets ["Miner" "Alice" "Bob"]. 
wallets=("Miner" "Alice" "Bob")

for name in ${wallets[@]}; do
$btr_cli createwallet $name &> /dev/null
done

# 2- Fondear las Wallets apartir de una recompensa de Mineria (50BTC).

miner_address=$($btr_cli -rpcwallet=Miner getnewaddress)

alice_address=$($btr_cli -rpcwallet=Alice getnewaddress)
bob_address=$($btr_cli -rpcwallet=Bob getnewaddress)

$btr_cli generatetoaddress 101 $miner_address &> /dev/null

utxo=($($btr_cli -rpcwallet=Miner listunspent | jq -c '.[0] | {txid, vout, amount}'))
utxo_txid=$(echo $utxo | jq -r '.txid')
utxo_vout=$(echo $utxo | jq -r '.vout')

# Transaccion para fondear las wallets ["Alice" "Bob"].
raw_tx_hex=$($btr_cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$utxo_txid'", "vout": '$utxo_vout'}]''' '''{"'$alice_address'": 24.9999, "'$bob_address'": 24.9999}''')
signed_tx_hex=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $raw_tx_hex | jq -r '.hex')
sent_txid=$($btr_cli -rpcwallet=Miner sendrawtransaction $signed_tx_hex)

$btr_cli generatetoaddress 1 $miner_address &> /dev/null

echo "=========Initial Alice Balance========="
$btr_cli -rpcwallet=Alice getbalance
echo "==========Initial Bob Balance=========="
$btr_cli -rpcwallet=Bob getbalance

# 3- Crear un wallet multisig ["Alice" "Bob"]

# Consiguiendo los descriptores wpkh
alice_desc=$($btr_cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | cut -d"(" -f2 | cut -d")" -f1 | sed 's/\/0\/\*/\/<0;1>\/\*/')
bob_desc=$($btr_cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | cut -d"(" -f2 | cut -d")" -f1 | sed 's/\/0\/\*/\/<0;1>\/\*/')

# Creando el output descriptor.
desc="wsh(multi(2,$alice_desc,$bob_desc))"
checksum=$($btr_cli getdescriptorinfo "$desc" | jq -r '.checksum')

output_desc="[{\"desc\": \"$desc#$checksum\", \"active\": true, \"timestamp\": \"now\", \"range\": [0,999]}]"

# Creando la wallet multisig en sin llaves privadas y blanco para luego importar el output descriptor.
$btr_cli createwallet "Multisig" true true &> /dev/null
$btr_cli -rpcwallet=Multisig importdescriptors "$output_desc" &> /dev/null

echo "========Initial Multisig Balance======="
$btr_cli -rpcwallet=Multisig getbalance

# 4- Crear una Partially Signed Bitcoin Transaction (PSBT) para fondear la wallet Multisig.

multisig_address=$($btr_cli -rpcwallet=Multisig getnewaddress)

# Buscar utxo para financiar el PSBT.
$btr_cli -rpcwallet=Alice listunspent &> /dev/null
$btr_cli -rpcwallet=Bob listunspent &> /dev/null

alice_utxo=($($btr_cli -rpcwallet=Alice listunspent | jq -c '.[0] | {txid, vout, amount}'))
bob_utxo=($($btr_cli -rpcwallet=Bob listunspent | jq -c '.[0] | {txid, vout, amount}'))

alice_utxo_txid=$(echo $alice_utxo | jq -r '.txid')
alice_utxo_vout=$(echo $alice_utxo | jq -r '.vout')
bob_utxo_txid=$(echo $bob_utxo | jq -r '.txid')
bob_utxo_vout=$(echo $bob_utxo | jq -r '.vout')

alice_change_address=$($btr_cli -rpcwallet=Alice getrawchangeaddress)
bob_change_address=$($btr_cli -rpcwallet=Bob getrawchangeaddress)

# Cada quien paga 10BTC, y pagan de fee cada uno 0.0001 saldo total gastado 20BTC + 0.0002 en FEE. Cada quien se queda con un cambio de 14.9998.
psbt=$($btr_cli -rpcwallet=Alice createpsbt '''[{"txid": "'$alice_utxo_txid'", "vout": '$alice_utxo_vout'}, {"txid": "'$bob_utxo_txid'", "vout": '$bob_utxo_vout'}]''' '''{"'$multisig_address'": 20, "'$alice_change_address'": 14.9998, "'$bob_change_address'": 14.9998}''')

echo -e "\n||||||||||||||||||||||||||||||||| \n"

echo "======================================="
echo "Ambos pagan 10BTC a la wallet Multisig."
echo "======================================="

# Procesar el psbt. Alice Actualiza y Firma luego le pasa su PSBT generado a Bob para que haga lo mismo. 
psbt_processed_alice=$($btr_cli -rpcwallet=Alice walletprocesspsbt $psbt | jq -r '.psbt')
psbt_processed_bob=$($btr_cli -rpcwallet=Bob walletprocesspsbt $psbt_processed_alice | jq -r '.psbt') 

# Bob finaliza el PSBT y lo transmite en la red.
psbt_tx_hex=$($btr_cli -rpcwallet=Bob finalizepsbt $psbt_processed_bob | jq -r '.hex')
psbt_txid=$($btr_cli -rpcwallet=Bob sendrawtransaction $psbt_tx_hex)

# 5- Confirmar la transaccion Minando 1 bloque.
$btr_cli generatetoaddress 1 $miner_address &> /dev/null

echo -e "\n||||||||||||||||||||||||||||||||| \n"

# 6- Mostrar Balance final.
echo "=========Final Alice Balance========="
$btr_cli -rpcwallet=Alice getbalance
echo "==========Final Bob Balance=========="
$btr_cli -rpcwallet=Bob getbalance
echo "========Final Multisig Balance======="
$btr_cli -rpcwallet=Multisig getbalance

# LIQUIDAR MULTISIG.

# 1- Crear una PSBT para gastar los fondos del Multisig wallet.
outpoint_json=$($btr_cli -rpcwallet=Multisig listunspent | jq -r '.[0]')
outpoint_txid=$(echo $outpoint_json | jq -r '.txid')
outpoint_vout=$(echo $outpoint_json | jq -r '.vout')

alice_new_address=$($btr_cli -rpcwallet=Alice getnewaddress)
multisig_change=$($btr_cli -rpcwallet=Multisig getrawchangeaddress)

withdraw_from_multisig=$($btr_cli -rpcwallet=Multisig createpsbt "[{\"txid\":\"$outpoint_txid\",\"vout\":$outpoint_vout}]" "{\"$alice_new_address\":3, \"$multisig_change\":16.9999}")
psbt_multisig=$($btr_cli -rpcwallet=Multisig walletprocesspsbt $withdraw_from_multisig | jq -r '.psbt')

# 2-3 Firmar PSBT por Alice y Bob
psbt_alice=$($btr_cli -rpcwallet=Alice walletprocesspsbt $psbt_multisig | jq -r '.psbt')   
psbt_bob=$($btr_cli -rpcwallet=Bob walletprocesspsbt $psbt_alice | jq -r '.psbt')   

echo "======================================="
echo "Alice Retirando 3BTC."
echo "======================================="

$btr_cli analyzepsbt $psbt_bob

# 4- Extraer la firma y transmitirla.
alice_raw_tx=$($btr_cli -rpcwallet=Alice finalizepsbt $psbt_bob | jq -r '.hex')
alice_txid=$($btr_cli -rpcwallet=Alice sendrawtransaction $alice_raw_tx)

$btr_cli -rpcwallet=Miner generatetoaddress 1 $miner_address &> /dev/null

# 5- Saldo Finales.

echo "=========New final Alice Balance========="  
$btr_cli -rpcwallet=Alice getbalance
echo "==========New final Bob Balance=========="
$btr_cli -rpcwallet=Bob getbalance
echo "========New final Multisig Balance======="
$btr_cli -rpcwallet=Multisig getbalance
