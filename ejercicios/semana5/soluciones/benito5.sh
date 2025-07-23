#!/bin/bash

bitcoind -daemon
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
   echo "Indique el NOMBRE de la wallet donde quiere crear la dirección:"
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

function send_to_address 
{
echo "Indique el NOMBRE de la wallet que va a RECIBIR para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
recibe=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label") 
echo "Cuántos bitcoins desean enviar a $name_wallet"
 read cantidad
bitcoin-cli -rpcwallet=Miner sendtoaddress $recibe $cantidad
}

function confirma_tx 
{
  bitcoin-cli "-rpcwallet=Miner" generatetoaddress 1 "$address"
}

function consult_utxos_vouts () 
{
cant_utxos=$(bitcoin-cli -rpcwallet=$1 listunspent | jq -r ". | length")
  echo "La WALLET $1 tiene $cant_utxos UTXOS"
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

function create_txs_sequence () 
{
echo "### Bienvenido al asistente de creación de TRANSACCIONES de Bitcoin ###"
echo "Indique el NOMBRE de la wallet que va a RECIBIR para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
recibe=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label") 

echo "Indique el NOMBRE de la wallet que va a RECIBIR EL CAMBIO para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
cambio=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label")

echo "Indique cuantos bitcoin va a enviar:"
  read enviar
echo "Indique el cambio de vuelta:"
  read cambio_vuelta
  
echo "Indique la altura de bloque para incluir el bloqueo"
  read sequence

rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}',
"sequence": '$sequence'}]''' outputs='''[{ "'$recibe'": '$enviar'},{ "'$cambio'": '$cambio_vuelta' }]''')
firmartx=$(bitcoin-cli -named -rpcwallet=$name_wallet signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
}

#### =================================> SOLUCIÓN <=============================== ####

echo "#### ¡BIENVENIDOS A BITCOIN DESDE LA LÍNEA DE COMANDOS ####"
echo ""

createwallet

echo "#### Crea una dirección en el wallet MINER para recibir la RECOMPENSA ####"
echo ""

createaddress

echo ""
echo "#### Emula el proceso de minado para fondear la wallet MINER ####"
echo ""

generarbloques

echo ""
echo "#### Enviar 50 bitcoins de MINER a ALICE ####"
echo ""

send_to_address
confirma_tx

echo ""
echo "El balance de ALICE ahora es:"
bitcoin-cli -rpcwallet=Alice getbalance

echo ""
echo "#### Enviar 10 bitcoins de ALICE a MINER ####"
echo ""

echo "Ingrese el nombre de la wallet (ALICE) en donde desea realizar la consulta de utxos y vouts"
  read wallet

consult_utxos_vouts $wallet
create_txs_sequence

##### Aparece error code: -26 error message: non-BIP68-final, esto significa que la transacción no tiene permitido #####
##### ser gastada debido al bloqueo #####

bitcoin-cli "-rpcwallet=Miner" generatetoaddress 10 "$address"
bitcoin-cli -named sendrawtransaction hexstring=$firmartx
bitcoin-cli getrawmempool true
bitcoin-cli "-rpcwallet=Miner" generatetoaddress 1 "$address"
echo ""
echo "El balance de Alice ahora es:"
bitcoin-cli -rpcwallet=Alice getbalance

bitcoin-cli stop
cd .bitcoin/
rm -r regtest/
