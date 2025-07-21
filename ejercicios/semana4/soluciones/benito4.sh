#!/bin/bash

#### ==========================> ARRANQUE DE BITCOIN CORE <======================== ####

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

function create_txs_locktime () 
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
  
echo "Indique la altura de bloque para incluir el LOCKTIME"
  read locktime

if (( cant_utxos <= 1 ));
  then
    rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}',
    "sequence": 1}]''' outputs='''[{ "'$recibe'": '$enviar'},{ "'$cambio'": '$cambio_vuelta' }]''' locktime=$locktime)
    firmartx=$(bitcoin-cli -named -rpcwallet=$name_wallet signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
    id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
  else
    rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}',
    "sequence":1}, {"txid":'${ids_utxos[1]}', "vout":'${vouts[1]}', "sequence":1} ]''' outputs='''[{ "'$recibe'":
    '$enviar'},{ "'$cambio'": '$cambio_vuelta' }]''' locktime=$locktime)
    firmartx=$(bitcoin-cli -named -rpcwallet=$name_wallet signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
    id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
fi
}

function create_txs_opreturn () 
{
echo "Indique el NOMBRE de la wallet que va a RECIBIR EL CAMBIO para crear la dirección:"
  read name_wallet
echo "Indique el LABEL que le desea asignar a la dirección:"
  read label
cambio=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label")

echo "Indique el cambio de vuelta:"
  read cambio_vuelta
  
op_return_data="837f5d1177fa44e8d67535d05a167ba3fce6c8f8c5c765e32c783a005f4684e8"
if (( cant_utxos <= 1 ));
  then
    rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}',
    "sequence": 1}]''' outputs='''{"data": "'$op_return_data'", "'$cambio'":'$cambio_vuelta' }''')
    bitcoin-cli -named decoderawtransaction hexstring=$rawtx
    firmartx=$(bitcoin-cli -named -rpcwallet=$name_wallet signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
    id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
  else
    rawtx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid":'${ids_utxos[0]}', "vout":'${vouts[0]}',
    "sequence":1}, {"txid":'${ids_utxos[1]}', "vout":'${vouts[1]}', "sequence":1} ]''' outputs='''{"data":
    "'$op_return_data'", "'$cambio'": '$cambio_vuelta' }''')
    bitcoin-cli -named decoderawtransaction hexstring=$rawtx
    firmartx=$(bitcoin-cli -named -rpcwallet=$name_wallet signrawtransactionwithwallet hexstring=$rawtx | jq -r '.hex')
    id_tx=$(bitcoin-cli -named sendrawtransaction hexstring=$firmartx)
fi
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
echo "#### Enviar 50 bitcoins de MINER a EMPLEADOR ####"
echo ""

send_to_address
confirma_tx

echo ""
echo "#### Enviar 40 bitcoins de EMPLEADOR a EMPLEADO con un LOCKTIME de 500 bloques ####"
echo ""

echo "Ingrese el nombre de la wallet (EMPLEADOR) en donde desea realizar la consulta de utxos y vouts"
  read wallet

consult_utxos_vouts $wallet
echo ""
create_txs_locktime

##### Aparece error code: -26 error message: non-final, esto significa que la transacción no tiene permitido #####
##### ir a la MEMPOOL ni ser gastada debido al LOCKTIME #####

bitcoin-cli "-rpcwallet=Miner" generatetoaddress 397 "$address"
bitcoin-cli -named sendrawtransaction hexstring=$firmartx
bitcoin-cli getrawmempool true
bitcoin-cli "-rpcwallet=Miner" generatetoaddress 1 "$address"
echo ""
echo "El balance de Miner ahora es:"
bitcoin-cli -rpcwallet=Miner getbalance
echo "El balance de Empleador ahora es:"
bitcoin-cli -rpcwallet=Empleador getbalance
echo "El balance de Empleado ahora es:"
bitcoin-cli -rpcwallet=Empleado getbalance

echo ""
echo "#### Crea una transacción de EMPLEADO A EMPLEADO, agrega en OP_RETURN lo siguiente:  ####"
echo "#### He recibido mi salario, ahora soy rico ####"
echo ""

echo "Ingrese el nombre de la wallet (EMPLEADO) en donde desea realizar la consulta de utxos y vouts"
  read wallet

consult_utxos_vouts $wallet
create_txs_opreturn
confirma_tx

echo ""
echo "El balance de Empleador ahora es:"
bitcoin-cli -rpcwallet=Empleador getbalance
echo "El balance de Empleado ahora es:"
bitcoin-cli -rpcwallet=Empleado getbalance

bitcoin-cli stop
cd .bitcoin/
rm -r regtest/
