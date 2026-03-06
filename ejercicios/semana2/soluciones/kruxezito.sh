#!/bin/bash

# Configurando Bitcoin-cli en un Alias para mayor comodidad.
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
# 1- Creando dos Billeteras Miner-Trader.
$btr_cli createwallet "Miner" > /dev/null 2>&1 || $btr_cli loadwallet "Miner" > /dev/null 2>&1
$btr_cli createwallet "Trader" > /dev/null 2>&1 || $btr_cli loadwallet "Trader" > /dev/null 2>&1

# Generando las address necesarias para este paso.
miner_address=$($btr_cli -rpcwallet=Miner getnewaddress "Miner Reward")
trader_address=$($btr_cli -rpcwallet=Trader getnewaddress "Receiver")
miner_change_address=$($btr_cli -rpcwallet=Miner getrawchangeaddress)

# 2- Fondeando miner address con el equivalente de 3 bloques minados.
$btr_cli -rpcwallet=Miner generatetoaddress 103 $miner_address &> /dev/null

# Mostrar Starting Balance.
starting_balance=$($btr_cli -rpcwallet=Miner getbalance)
echo "Starting Balance: $starting_balance"

# Seleccionando los UTXO que tengan exactamente 50BTC de Amount.
utxos=($($btr_cli -rpcwallet=Miner listunspent | jq -c '.[] | select(.amount==50.00000000) | { txid, vout }'))

# Separando utxo1/utxo2
utxo_txid1=$(echo ${utxos[0]} | jq -r '.txid')
utxo_vout1=$(echo ${utxos[0]} | jq -r '.vout')
utxo_txid2=$(echo ${utxos[1]} | jq -r '.txid')
utxo_vout2=$(echo ${utxos[1]} | jq -r '.vout')

# 3- Creando la transaccion 'parent' con nSequence=1 para asegurarme que este activo el campo BIP-125 (RBF). Aunque las versiones recientes de Core son full-rbf. Una señalizacion explicita asegura la compatibilidad de este ejercicio.
parent_hex_tx=$($btr_cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$utxo_txid1'", "vout": '$utxo_vout1', "sequence": 1}, {"txid": "'$utxo_txid2'", "vout": '$utxo_vout2', "sequence": 1}]''' '''{"'$trader_address'": 70, "'$miner_change_address'": 29.99999}''')

# 4- Firmando y Transmitiendo la transaccion 'parent'.
signed_parent=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $parent_hex_tx | jq -r '.hex')
parent_txid=$($btr_cli -rpcwallet=Miner sendrawtransaction $signed_parent)

# Conseguir el fee base.
txfee=$($btr_cli -rpcwallet=Miner getmempoolentry $parent_txid | jq -r '.fees.base')

# Aqui hago una sola llamada del getrawtransaction y lo guardo en una variable para mayor flexibilidad y rendimiento.
raw_tx=$($btr_cli getrawtransaction $parent_txid 1)

# 5/6- Crear y Mostrar en pantalla el json.
echo -e "Mempool Details: \n"
echo $raw_tx | jq -r --arg FEE $txfee '{"input": [.vin[] | {txid, vout}], "output": [.vout[] | {"script_pubkey": .scriptPubKey.hex, "amount": .value}], "Fees": $FEE | tonumber, "Weight": .weight }'

# Consiguiendo el vout para la transaccion CPFP.
parent_vout=$(echo $raw_tx | jq -r --arg ADDRESS $miner_change_address '.vout[] | select(.scriptPubKey.address == $ADDRESS) | .n')

# Nueva address del minero.
miner_new_address=$($btr_cli -rpcwallet=Miner getnewaddress)

# 7- Creando y transmitiendo la TxHija con un poco mas de fee para pagar por su 'parent'.
child_hex_tx=$($btr_cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$parent_txid'", "vout": '$parent_vout'}]''' '''{"'$miner_new_address'": 29.99998}''')
signed_children=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $child_hex_tx | jq -r '.hex')
child_txid=$($btr_cli -rpcwallet=Miner sendrawtransaction $signed_children)

# 8- Consulta al mempool y mostrar salida.
$btr_cli getmempoolentry $child_txid | jq '.'

# Nuevos destinos para RBF.
trader_new_address=$($btr_cli -rpcwallet=Trader getnewaddress)
miner_new_change_address=$($btr_cli -rpcwallet=Miner getrawchangeaddress)

# 9- Transaccion RBF, Utilizando los mismos UTXO de la transaccion 'parent' y con diferentes destinos pero pagando 10 veces mas el fee que 'parent'. 
rbf_hex_tx=$($btr_cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$utxo_txid1'", "vout": '$utxo_vout1', "sequence": 1}, {"txid": "'$utxo_txid2'", "vout": '$utxo_vout2', "sequence": 1}]''' '''{"'$trader_new_address'": 70, "'$miner_new_change_address'": 29.9999}''')

# 10- Firmar y transmitir la nueva transaccion main.
signet_rbf=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $rbf_hex_tx | jq -r '.hex')
main_txid=$($btr_cli -rpcwallet=Miner sendrawtransaction $signet_rbf)

# 11- Consulta a mempool para ver como se comporta child.
$btr_cli getmempoolentry $child_txid | jq '.'

# 12- Explicacion sobre que cambio comparada con su primer consulta a la mempool.
echo -e "\n"
echo "---------------------------- EXPLICACION ----------------------------"
echo -e "Al realizar RBF sobre la transacción 'parent', esta es eliminada del mempool y reemplazada por una nueva. \nLa transacción 'child' dependía del txid de la 'parent' original. Al desaparecer el padre original, \nla 'child' se vuelve inválida (intenta gastar un output que ya no existe en el mempool) y es expulsada. \nPor eso el último comando 'getmempoolentry' devuelve el error: Transaction not in mempool."
