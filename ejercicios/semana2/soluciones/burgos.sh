#!/bin/bash

echo "Iniciando"

#Reiniciando regtest con nuevas variables
bitcoin-cli stop
sleep 1
rm -R ~/.bitcoin/regtest/

bitcoind -daemon
sleep 3
bitcoin-cli createwallet "Miner" > /dev/null
bitcoin-cli createwallet "Trader" > /dev/null
miner_address=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
echo "Miner address " $miner_address
trader_address=$(bitcoin-cli -rpcwallet="Trader" getnewaddress "Recibido")
echo "Trader address" $trader_address
bitcoin-cli -rpcwallet=Miner generatetoaddress 103 $miner_address > /dev/null


blocks=0
balance_miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
#echo $balance_miner

unspent_miner=$(bitcoin-cli -rpcwallet=Miner listunspent)
#echo $unspent_miner

txid00=$(echo "$unspent_miner" | jq -r '.[0].txid')
vout00=$(echo "$unspent_miner" | jq -r '.[0].vout')
txid01=$(echo "$unspent_miner" | jq -r '.[1].txid')
vout01=$(echo "$unspent_miner" | jq -r '.[1].vout')

#Crear transaccion
parenttx=$(bitcoin-cli createrawtransaction "[{\"txid\":\"$txid00\",\"vout\":$vout00}, {\"txid\":\"$txid01\",\"vout\":$vout01}]" \
  "{\"$trader_address\":70, \"$miner_address\":29.99999}")

#Firmar transaccion
signedtx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$parenttx")
signedtx_hex=$(echo "$signedtx "| jq -r '.hex')

#echo "Enviar la transaccion a la mempool"
bitcoin-cli sendrawtransaction $signedtx_hex > /dev/null
#echo $signedtx_hex

#Consulta transaccion en mempool

mempool_tx=$(bitcoin-cli getrawmempool | jq -r '.[]')

decode_tx=$(bitcoin-cli decoderawtransaction $parenttx)

decode_vout0=$(echo "$decode_tx" | jq -r '.vout[0]')

decode_vout1=$(echo "$decode_tx" | jq -r '.vout[1]')

#bitcoin-cli getmempoolinfo 
echo "{
  \"input\": [
  {
    \"txid\": $txid00,
    \"vout\": $vout00
  },
  {
    \"txid\": $txid01,
    \"vout\": $vout01
  }
  ],
  \"output\": [
  {
    \"script_pubkey\": $(echo $decode_vout0 | jq -r '.scriptPubKey'),
    \"amount\": $(echo $decode_vout0 | jq -r '.value')
  },
  {
    \"script_pubkey\": $(echo $decode_vout1 | jq -r '.scriptPubKey'),
    \"amount\": $(echo $decode_vout1 | jq -r '.value')
  }
  ],
  \"Fees\": $(bitcoin-cli getmempoolinfo | jq -r '.total_fee')  ,
  \"Weight\": $(echo "$decode_tx" | jq -r '.vsize')
}"

miner_address_child=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Child")
echo "\n\nMiner address child: " $miner_address

txid_outparent=$(echo $decode_tx | jq -r '.txid')
vout_outparent=$(echo $decode_tx | jq -r '.vout[1].n')


childtx=$(bitcoin-cli createrawtransaction "[{\"txid\":\"$txid_outparent\",\"vout\":$vout_outparent}]" "{\"$miner_address_child\":29.99998}")
#echo "Child tx" $childtx

#Firmar y transmitir tx child
signedtx_child=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$childtx")
signedtx_hex_child=$(echo "$signedtx_child "| jq -r '.hex')

#Enviar tx child a la mempool"
hash_child=$(bitcoin-cli sendrawtransaction $signedtx_hex_child)

#Imprimir mempoolentry
echo -e "\n\nGetmempoolentry transaccion Child"
bitcoin-cli getmempoolentry $hash_child
mempool=$(bitcoin-cli getrawmempool true)

#Nueva transacción conflictiva
rbftx=$(bitcoin-cli createrawtransaction "[{\"txid\":\"$txid00\",\"vout\":$vout00}, {\"txid\":\"$txid01\",\"vout\":$vout01}]" \
  "{\"$trader_address\":70, \"$miner_address\":29.99989000}")

#signedtx_rbftx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$rbftx")
#Firmar y transmitir nueva transacción
signed_rbftx=$(echo $(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$rbftx") | jq -r '.hex')
hash_rbftx=$(bitcoin-cli sendrawtransaction $signed_rbftx)

#Imprimir mempoolentry luego de crear la transaccion RBF
echo -e "\nGetmempoolentry transaccion Child, luego de hacer RBF"
bitcoin-cli getmempoolentry $hash_child
echo -e "--------------------------------------------------\n\n"
echo -e "\nError al tratar de consultar getmempoolentry de la tx Child"

#echo -e "\nGetmempoolentry transaccion RBF"
#bitcoin-cli getmempoolentry $hash_rbftx

echo -e "\nSe ha eliminado la transaccion child de la Mempool"
echo "Child usaba un UTXO de la salida de la transaccion Parent, al reemplazar la transacción Parent por otra con un fee mayor, son eliminadas ambas de la Mempool"
echo "Podemos confirmarlo mostrando la mempool luego de transmitir las tx Parent y Child: \n"
echo $mempool
echo -e "\n\n--------------------------------------------------"
echo -e "\n A diferencia de la mempool en el estado actual (Despues de transmitir la tx con RBF):"
bitcoin-cli getrawmempool true
echo -e "\nVerificamos que la transacción Parent fue sustituida por una transacción que paga un fee de 11.000 sats y por consecuencia la tx Child fue eliminada"

