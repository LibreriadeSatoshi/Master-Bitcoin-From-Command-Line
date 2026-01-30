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

#### ===========================> SOLUCIÓN PRIMERA PARTE <========================= ####

echo "################ PRIMERA PARTE DEL EJERCICIO ################"
echo ""
echo "##### ¡BIENVENIDOS A BITCOIN DESDE LA LÍNEA DE COMANDOS #####"
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
echo "#### Enviar 15 bitcoins de MINER a ALICE ####"
echo ""

send_to_address

echo ""
echo "#### Enviar 15 bitcoins de MINER a BOB ####"
echo ""

send_to_address
confirma_tx

echo ""
echo "El balance de Miner ahora es:"
bitcoin-cli -rpcwallet=Miner getbalance
echo "El balance de Alice ahora es:"
bitcoin-cli -rpcwallet=Alice getbalance
echo "El balance de Bob ahora es:"
bitcoin-cli -rpcwallet=Bob getbalance
echo ""

################# GENERACIÓN DE LOS DESCRIPTORES PARA CREAR MULTISIGN #########################

wallets=(Alice Bob)

declare -A xpubs

for ((n=1;n<=2;n++))
  do
    xpubs["internal_xpub_${wallets[n-1]}"]=$(bitcoin-cli -rpcwallet=${wallets[n-1]} listdescriptors | jq '.descriptors |  
    [.[] |  select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')

    xpubs["external_xpub_${wallets[n-1]}"]=$(bitcoin-cli -rpcwallet=${wallets[n-1]} listdescriptors | jq '.descriptors | 
    [.[] |    select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')
done

external_desc="wsh(multi(2,${xpubs["external_xpub_${wallets[0]}"]},${xpubs["external_xpub_${wallets[1]}"]}))"
internal_desc="wsh(multi(2,${xpubs["internal_xpub_${wallets[0]}"]},${xpubs["internal_xpub_${wallets[1]}"]}))"

external_desc_sum=$(bitcoin-cli getdescriptorinfo $external_desc | jq '.descriptor')
internal_desc_sum=$(bitcoin-cli getdescriptorinfo $internal_desc | jq '.descriptor')

multisig_ext_desc="{\"desc\": $external_desc_sum, \"active\": true, \"internal\": false, \"timestamp\": \"now\"}"
multisig_int_desc="{\"desc\": $internal_desc_sum, \"active\": true, \"internal\": true, \"timestamp\": \"now\"}"

multisig_desc="[$multisig_ext_desc, $multisig_int_desc]"

################# CREACIÓN DE LA WALLET MULTISIG #######################

bitcoin-cli -named createwallet wallet_name="MultiSign" disable_private_keys=true blank=true

bitcoin-cli -rpcwallet="MultiSign" importdescriptors "$multisig_desc"
   
echo "####### INFORMACIÓN DE LA WALLET MULTISIGN CREADA #######"

bitcoin-cli -rpcwallet="MultiSign" getwalletinfo

echo ""
echo "#### Crea una dirección en el wallet MultiSign para recibir la TRANSACCIÓN ####"
createaddress
echo ""

txid_Alice=$(bitcoin-cli -rpcwallet=Alice listunspent | jq ".[0] | .txid")
vout_Alice=$(bitcoin-cli -rpcwallet=Alice listunspent | jq ".[0] | .vout")

txid_Bob=$(bitcoin-cli -rpcwallet=Bob listunspent | jq ".[0] | .txid")
vout_Bob=$(bitcoin-cli -rpcwallet=Bob listunspent | jq ".[0] | .vout")

addr_Alice=$(bitcoin-cli -rpcwallet=Alice getnewaddress)
addr_Bob=$(bitcoin-cli -rpcwallet=Bob getnewaddress)

psbt=$(bitcoin-cli -named createpsbt inputs='''[ { "txid": '$txid_Alice', "vout": '$vout_Alice' }, { "txid": '$txid_Bob', "vout": '$vout_Bob' } ]''' outputs='''[ { "'$address'": 20 }, {"'$addr_Alice'": 4.999995}, {"'$addr_Bob'": 4.999995} ]''')

bitcoin-cli -named decodepsbt psbt=$psbt

bitcoin-cli -named analyzepsbt psbt=$psbt

psbt_Alice=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $psbt | jq '.psbt')

psbt_Bob=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $psbt | jq '.psbt')

combined_psbt=$(bitcoin-cli combinepsbt '''['$psbt_Alice', '$psbt_Bob']''')

finalized_psbt_hex=$(bitcoin-cli finalizepsbt $combined_psbt | jq -r '.hex')

bitcoin-cli sendrawtransaction $finalized_psbt_hex

confirma_tx

saldo_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
saldo_Bob=$(bitcoin-cli -rpcwallet=Bob getbalance)
echo ""
echo "##### El nuevo saldo de Alice es: #####"
echo "$saldo_Alice bitcoins"
echo "##### El nuevo saldo de Bob es: #####"
echo "$saldo_Bob bitcoins"

#### ===========================> SOLUCIÓN SEGUNDA PARTE <========================= ####

echo ""
echo "#################### SEGUNDA PARTE DEL EJERCICIO ####################"
echo ""
echo "#### Crea una dirección en el wallet Alice para recibir la TRANSACCIÓN ####"
echo ""
createaddress
echo ""

addr_Multi=$(bitcoin-cli -rpcwallet=MultiSign getnewaddress)

psbt=$(bitcoin-cli -named -rpcwallet=MultiSign walletcreatefundedpsbt outputs='''[ { "'$address'": 3 }, {"'$addr_Multi'": 16.9999} ]''' | jq -r '.psbt')

bitcoin-cli -named decodepsbt psbt=$psbt

bitcoin-cli -named analyzepsbt psbt=$psbt

psbt_Alice=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $psbt | jq '.psbt')

psbt_Bob=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $psbt | jq '.psbt')

combined_psbt=$(bitcoin-cli combinepsbt '''['$psbt_Alice', '$psbt_Bob']''')

finalized_psbt_hex=$(bitcoin-cli finalizepsbt $combined_psbt | jq -r '.hex')

bitcoin-cli sendrawtransaction $finalized_psbt_hex

confirma_tx

saldo_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
saldo_Bob=$(bitcoin-cli -rpcwallet=Bob getbalance)
echo ""
echo "##### El nuevo saldo de Alice es: #####"
echo "$saldo_Alice bitcoins"
echo "##### El nuevo saldo de Bob es: #####"
echo "$saldo_Bob bitcoins"

