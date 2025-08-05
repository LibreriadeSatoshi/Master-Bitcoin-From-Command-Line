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
bitcoin-cli createwallet "Empleado" > /dev/null
bitcoin-cli createwallet "Empleador" > /dev/null

#Generar direcciones y fondear
miner_address=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
empleado_address=$(bitcoin-cli -rpcwallet="Empleado" getnewaddress "salario")
empleador_address=$(bitcoin-cli -rpcwallet="Empleador" getnewaddress "ganacia")

#Fondear al empleador
bitcoin-cli -rpcwallet=Miner generatetoaddress 102 $miner_address > /dev/null
bitcoin-cli -rpcwallet=Miner sendtoaddress $empleador_address 50
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null

balance_miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Balance miner:" $balance_miner
balance_empleador=$(bitcoin-cli -rpcwallet=Empleador getbalance)
echo "Balance empleador:" $balance_empleador

unspent_empleador=$(bitcoin-cli -rpcwallet=Empleador listunspent)
#echo $unspent_empleador

txid00=$(echo "$unspent_empleador" | jq -r '.[0].txid')
vout00=$(echo "$unspent_empleador" | jq -r '.[0].vout')

#Transacción con timelock 500
timelock_tx=$(bitcoin-cli createrawtransaction \
  "[{\"txid\":\"$txid00\",\"vout\":$vout00}]" \
  "{\"$empleado_address\":40, \"$empleador_address\":9.99999}"\
  500)

#Firmar transaccion
signedtx=$(bitcoin-cli -rpcwallet=Empleador signrawtransactionwithwallet "$timelock_tx")
#echo $signedtx

signedtx_hex=$(echo "$signedtx "| jq -r '.hex')

#"Enviar la transaccion a la mempool"
hash_tx=$(bitcoin-cli sendrawtransaction $signedtx_hex)
echo $hash_tx
echo -e "\n\n La transaccion no se puede transmitir por el timelock, debemos minar hasta el bloque 500 para poder transmitirla"
echo -e "\nMinamos 400 bloques adicionales..."
bitcoin-cli -rpcwallet=Miner generatetoaddress 400 $miner_address > /dev/null

#Retransmitir y minar un bloque, luego de minar por lo menos 500 bloques
hash_tx=$(bitcoin-cli sendrawtransaction $signedtx_hex)
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null

empleador_change=$(bitcoin-cli -rpcwallet=Empleador getnewaddress "Change")

unspent_empleado=$(bitcoin-cli -rpcwallet=Empleado listunspent)
txid01=$(echo "$unspent_empleado" | jq -r '.[0].txid')
vout01=$(echo "$unspent_empleado" | jq -r '.[0].vout')

#Mensaje a hex
op_return=$(echo "He recibido mi salario, ahora soy rico" | xxd -p | tr -d '\n')

#Transacción con timelock 500
op_return_tx=$(bitcoin-cli createrawtransaction \
  "[{\"txid\":\"$txid01\",\"vout\":$vout01}]" \
  "{\"$empleador_change\":39.99999, \"data\":\"$op_return\"}")
echo "OP_RETURN tx: "$op_return_tx

#Firmar transaccion
signedtx=$(bitcoin-cli -rpcwallet=Empleado signrawtransactionwithwallet "$op_return_tx")
signedtx_hex=$(echo "$signedtx "| jq -r '.hex')

#"Enviar la transaccion a la mempool y minar un bloque adicional
hash_tx=$(bitcoin-cli sendrawtransaction $signedtx_hex)

txid=$(bitcoin-cli getrawmempool | jq -r '.[]')
echo "Txid " $txid
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null


balance_miner=$(bitcoin-cli -rpcwallet=Empleado getbalance)
echo "Balance empleado:" $balance_miner
balance_empleador=$(bitcoin-cli -rpcwallet=Empleador getbalance)
echo "Balance empleador:" $balance_empleador
#Verificar el mensaje en OP_RETURN de la transacción
data_string=$(bitcoin-cli getrawtransaction $hash_tx true \
  | jq -r '.vout[] | select(.scriptPubKey.asm | startswith("OP_RETURN")) | .scriptPubKey.asm' \
  | cut -d' ' -f2 \
  | xxd -r -p)
echo $data_string