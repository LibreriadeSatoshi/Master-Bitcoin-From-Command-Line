#!/bin/bash
#### =================================> FUNCIONES <=============================== ####

function createwallet 
{
   echo "### Bienvenido al asistente de creación de WALLETS de Bitcoin ###"
   echo "¿Cuántas wallets quieres crear?"
     read cant_wallets
   echo "Vas a crear $cant_wallets wallets"

   for (( counter=$cant_wallets; counter>0; counter-- ))
     do
       echo "Ingrese el nombre de la wallet"
         read name_wallet
       echo "Usted va a crear una wallet con este nombre: "$name_wallet""
   if bitcoin-cli createwallet "$name_wallet"; then
       echo "La wallet "$name_wallet" fue creada correctamente"
   else
       echo "Ocurrió un error en la creación de la wallet: "$name_wallet""
   fi
   done
   wallets=$(bitcoin-cli listwallets)
   echo ""
   echo "Se crearon las siguentes wallets: $wallets"
}

function createaddress 
{
   echo "### Bienvenido al asistente de creación de DIRECCIONES de Bitcoin ###"
   echo "Indique el NOMBRE de la wallet (Miner) donde quiere crear la dirección:"
     read name_wallet
   echo "Indique el LABEL que le desea asignar a la dirección:"
     read label
     
   if address=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label") ; then
     echo "La dirección "$label" fue creada correctamente:"
     echo "$address"
   else
     echo "Ocurrió un error en la creación de la dirección "$label"."
   fi
}

function generarbloques 
{
   echo "### Bienvenido al asistente de creación de BLOQUES de Bitcoin ###"
   echo "Ingrese la wallet (Miner) que va a usar para recibir la recompensa :"
     read wallet
   echo "Ingrese la dirección para recibir la recompensa:"
     read address
   echo "Ingrese cuantos bitcoins desea minar:"
     read meta
   balance=$(bitcoin-cli "-rpcwallet=$wallet" getbalance)
   meta=$meta
   while [ "$(bc <<< "$balance < $meta")" == "1" ];
     do
       echo $balance
       bitcoin-cli "-rpcwallet=$wallet" generatetoaddress 1 "$address"
       balance=$(bitcoin-cli "-rpcwallet=$wallet" getbalance)
       balance=$(bc <<< "$balance")
   done
   echo ""
   echo "### El nuevo balance en tu wallet $wallet es de $balance bitcoins. ###"
   bloques=$(bitcoin-cli getblockchaininfo | jq -r '.blocks')
   echo "Se necesitaron $bloques bloques para minar los primeros $balance bitcoins."
}

function consult_utxos_vouts () 
{
cant_utxos=$(bitcoin-cli -rpcwallet=$1 listunspent | jq -r ". | length")
  echo "Esta WALLET tiene $cant_utxos UTXOS"
utxos=()
for (( counter=0; counter<$cant_utxos; counter++ ));
  do
    utxos+=($counter)
done 
ids_utxos=()
for i in "${utxos[@]}";
     do
       txid=$(bitcoin-cli -rpcwallet=$1 listunspent | jq ".[$i] | .txid")
       ids_utxos+=($txid)
done
vouts=()
for i in "${utxos[@]}";
     do
       vout=$(bitcoin-cli -rpcwallet=$1 listunspent | jq ".[$i] | .vout")
       vouts+=($vout)
done
}

function create_txs () 
{
echo "### Bienvenido al asistente de creación de TRANSACCIONES de Bitcoin ###"
echo "Indique el NOMBRE de la wallet que va a RECIBIR (Trader) para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
recibe=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label") 

echo "Indique el NOMBRE de la wallet que va a RECIBIR EL CAMBIO (Miner) para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
cambio=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label")

echo "Indique cuantos bitcoin va a enviar:"
  read enviar
echo "Indique el cambio de vuelta:"
  read cambio_vuelta

rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}', "sequence":1}, {"txid":'${ids_utxos[1]}', "vout":'${vouts[1]}', "sequence":1} ]''' outputs='''[{ "'$recibe'": '$enviar'},{ "'$cambio'": '$cambio_vuelta' }]''')
firmartx=$(bitcoin-cli -named -rpcwallet=Miner signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
}

function extract_key_values 
{
script_pubkey_trader=$(bitcoin-cli -named decoderawtransaction hexstring=$rawtx | jq -r '.vout[0] | .scriptPubKey')
script_pubkey_miner=$(bitcoin-cli -named decoderawtransaction hexstring=$rawtx | jq -r '.vout[1] | .scriptPubKey')
amount_trader=$(bitcoin-cli -named decoderawtransaction hexstring=$rawtx | jq -r '.vout[0] | .value')
amount_miner=$(bitcoin-cli -named decoderawtransaction hexstring=$rawtx | jq -r '.vout[1] | .value')
fees=$(bitcoin-cli getrawmempool true | jq -r '.[] | .fees | .base')
weight=$(bitcoin-cli getrawmempool true | jq -r '.[] | .vsize')
}

#### =================================> SOLUCIÓN <=============================== ####

createwallet

createaddress

generarbloques

echo "Ingrese el nombre de la wallet (Miner) en donde desea realizar la consulta de utxos y vouts"
  read wallet

consult_utxos_vouts $wallet

create_txs

extract_key_values 

echo '{"input": [{"txid": '"${ids_utxos[0]}"',"vout": '"${vouts[0]}"'},{"txid": '"${ids_utxos[1]}"',"vout":'"${vouts[1]}"'}],
       "output": [{"script_pubkey":'"$script_pubkey_miner"',"amount": '"$amount_miner"'},    
       {"script_pubkey":'"$script_pubkey_trader"',"amount": '"$amount_trader"'}],
       "Fees": '"$fees"',"Weight":'"$weight"'}' | jq '.'

echo ""
echo "############### NUEVA TRANSACCIÓN ################"
echo ""

create_txs

bitcoin-cli getmempoolentry $id_tx
wtxid_1=$(bitcoin-cli getmempoolentry $id_tx | jq -r '.wtxid')
fees_1=$(bitcoin-cli getmempoolentry $id_tx | jq -r '.fees | .base')

echo ""
echo "############### NUEVA TRANSACCIÓN (RBF) ################"
echo ""

create_txs

echo ""
bitcoin-cli getmempoolentry $id_tx
wtxid_2=$(bitcoin-cli getmempoolentry $id_tx | jq -r '.wtxid')
fees_2=$(bitcoin-cli getmempoolentry $id_tx | jq -r '.fees | .base')

echo ""
echo "########## EXPLICACIÓN DE LO QUE CAMBIA CUANDO SE HACE LA CONSULTA GETMEMPOOLENTRY: ##########"
echo ""
echo -e "#### Lo que cambia cuando se revisa la información que devuelve el comando getmempoolentry ####\n#### son los campos wtxid y fees, esto es dedido a que se entienden como transacciones     ####\n#### diferentes y se ha modificado las tarifas para acelerar la transacción usando RBF.    ####"
echo ""     
echo "#### DATOS DE LA TRANSACCIÓN CHILD 1 ####"
echo "wtxid = $wtxid_1"
echo "fees = $fees_1"
echo ""
echo "#### DATOS DE LA TRANSACCIÓN CHILD 2 ####"
echo "wtxid = $wtxid_2"
echo "fees = $fees_2"
