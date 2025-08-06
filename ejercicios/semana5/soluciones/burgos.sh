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

#Generar direcciones y fondear
miner_address=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
alice_address=$(bitcoin-cli -rpcwallet="Alice" getnewaddress "Billetera")

#Fondear al empleador
bitcoin-cli -rpcwallet=Miner generatetoaddress 101 $miner_address > /dev/null
bitcoin-cli -rpcwallet=Miner sendtoaddress $alice_address 30
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null


balance_miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Balance miner:" $balance_miner
balance_alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
echo "Balance Alice:" $balance_alice

unspent_alice=$(bitcoin-cli -rpcwallet=Alice listunspent)

txid00=$(echo "$unspent_alice" | jq -r '.[0].txid')
vout00=$(echo "$unspent_alice" | jq -r '.[0].vout')

#Transacción con timelock relativo 10 bloques
timelock_tx=$(bitcoin-cli createrawtransaction \
  "[{\"txid\":\"$txid00\",\"vout\":$vout00,\"sequence\":10}]" \
  "{\"$miner_address\":10, \"$alice_address\":19.99999}")

#Firmar transaccion
signedtx=$(bitcoin-cli -rpcwallet=Alice signrawtransactionwithwallet "$timelock_tx")
#echo $signedtx

signedtx_hex=$(echo "$signedtx "| jq -r '.hex')

#"Enviar la transaccion a la mempool"
hash_tx=$(bitcoin-cli sendrawtransaction $signedtx_hex)
echo $hash_tx
echo -e "\n\n La transaccion no se puede transmitir por el timelock relativo, debemos minar 10 bloques adicionales"
echo -e "\nMinamos 10 bloques adicionales..."
bitcoin-cli -rpcwallet=Miner generatetoaddress 10 $miner_address > /dev/null

echo -e "\nRetransmitir y minar un bloque"
hash_tx=$(bitcoin-cli sendrawtransaction $signedtx_hex)
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null



balance_alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
echo "Balance Alice:" $balance_alice
