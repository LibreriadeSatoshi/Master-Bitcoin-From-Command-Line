#!/bin/bash
cd Downloads/

#### =================================> FUNCIONES <=============================== ####

function downloads 
{
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS.asc
}

function verification 
{
   sha256sum --ignore-missing --check SHA256SUMS
   gpg --verify SHA256SUMS.asc
}

function installation 
{
   tar -zxvf bitcoin-29.0-x86_64-linux-gnu.tar.gz #Extrae los archivos comprimidos.
   sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*
}

function configuration 
{
   mkdir /home/andres/.bitcoin/
   cd /home/andres/.bitcoin/
   echo -e  "regtest=1 \nfallbackfee=0.0001 \nserver=1 \ntxindex=1" > bitcoin.conf
}

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

   if address=$(bitcoin-cli "-rpcwallet=$name_wallet" getnewaddress "$label"); then
     echo "La dirección "$label" fue creada correctamente:"
     echo "$address"
   else
     echo "Ocurrió un error en la creación de la dirección "$label"."
   fi
}

function generarbloques 
{
   echo "### Bienvenido al asistente de creación de BLOQUES de Bitcoin ###"
   echo "Ingrese la wallet que va a usar para recibir:"
     read wallet
   echo "Ingrese la dirección (copia y pega) para recibir la recompensa:"
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

function txs {
   echo "#### Bienvenido al asistente de GENERACIÓN de transacciones de bitcoin ####"
   echo "Ingrese el nombre de la wallet que va a ENVIAR:"
     read name_wallet
   echo "Ingrese la dirección (copia y pega) que va a recibir:"
     read address
   echo "Ingrese la cantidad a enviar:"
     read cantidad
   bitcoin-cli "-rpcwallet=$name_wallet" sendtoaddress $address $cantidad
}

function resumentx {
   echo "#### Bienvenido al asistente de CONSULTA de transacciones de bitcoin ####"
   echo "Ingrese el ID (copia y pega) de la transacción a consultar:"
     read ID
   echo "Ingrese la wallet (MINER) a consultar:"
     read wallet 
   txid=$(bitcoin-cli "-rpcwallet=$wallet" gettransaction "$ID" | jq -r '.txid')
   echo "#### El ID de la transacción es: ####"
   echo "$txid"

   enviado=$(bitcoin-cli "-rpcwallet=$wallet" gettransaction "$ID" | jq -r '.amount')
   echo "#### El valor enviado en la transacción es de: ####"
   echo "$enviado BTC"

   direccion=$(bitcoin-cli "-rpcwallet=$wallet" gettransaction "$ID" | jq -r '.details[] | .address')
   echo "#### La dirección que recibió es: ####"
   echo "$direccion"

   altura=$(bitcoin-cli "-rpcwallet=$wallet" gettransaction "$ID"  | jq -r '.blockheight')
   echo "#### La altura de bloque en el que ingresó la TX es: ####"
   echo "$altura"

   fee=$(bitcoin-cli "-rpcwallet=$wallet" gettransaction "$ID"  | jq -r '.fee')
   echo "#### La comisión pagada es: ####"
   echo "$fee"

   balanceminer=$(bitcoin-cli "-rpcwallet=$wallet" getbalance)
   echo "#### El balance en la wallet MINER es: ####"
   echo "$balanceminer"

   balancetrader=$(bitcoin-cli "-rpcwallet=Trader" getbalance)
   echo "#### El balance en la wallet TRADER es: ####"
   echo "$balancetrader"
}

#### =================> DESARROLLO DEL EJERCICIO <===================== ####

#### Las siguientes líneas descargan los binarios necesario para instalar #### 
#### BITCOIN CORE  ###########################################################

if downloads; then
   echo "######### La descarga de los binarios fue exitosa. #########"
else
   echo "######### Falló la descarga #########"
fi

#### Las siguientes líneas verifican los archivos descargados ############### 

if verification; then
   echo "######### Verificación exitosa de la firma binaria #########"
else
   echo "######### Falló la verificación #########"
fi

#### Las siguientes líneas instalan BITCOIN CORE ########################### 

if installation; then
   echo "######### La instalación ha sido exitosa #########"
else
   echo "######### La instalación ha fallado #########"
fi

#### Las siguientes líneas configuran BITCOIN CORE en modo REGTEST ######## 

if configuration; then
   echo "######### La configuración fue exitosa #########"
else
   echo "######### Falló la configuración #########"
fi

#### ===============> INICIO DE BITCOIND EN MODO DAEMON <=================== ####

bitcoind -daemon

#### =============> CREACIÓN DE WALLETS, DIRECCIONES Y TXS <================= ####

createwallet

echo "#### Creación de la DIRECCIÓN para recibir la recompensa de MINERÍA ####"
createaddress

generarbloques

#### Después de hacer unas correcciones a la función "generarbloques" y entender mejor como funciona ####
#### el nodo en modo "REGTEST" vi que tomo 101 bloques encontrar la primer recompensa de 50 bitcoins.####

echo "#### Creación de la DIRECCIÓN para recibir la TRANSACCIÓN ####"
createaddress

txs

#### Consulta el estado de la mempool para ver la transacción en espera. ####
echo "Las siguientes transacciones se encuentran en la MEMPOOL:"
bitcoin-cli getrawmempool

#### Genera un nuevo bloque para minar la transacción. ####
echo "Se ha generado el siguente bloque:"
bitcoin-cli "-rpcwallet=Miner" generatetoaddress 1 "bcrt1qvam7knlttshee8qckqaqxcn8309tfzdv7nsmw7"

resumentx
