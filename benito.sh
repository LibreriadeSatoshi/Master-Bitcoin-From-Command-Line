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
   echo "Se crearon las siguentes wallets: $wallets"
}

function createaddress 
{
   echo "### Bienvenido al asistente de creación de direcciones de Bitcoin ###"
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

#Intente hacer este loop para generar los bloques y no me funcionó, no he podido encontrar la 
#razón por la que se va al infinito.

function generarbloques 
{
   echo "Ingrese la wallet que va a usar para recibir:"
     read wallet
   echo "Ingrese la dirección para recibir la recompensa:"
     read address
   echo "Ingrese cuantos bitcoins desea minar:"
     read meta
   balance=$(bitcoin-cli "-rpcwallet=$wallet" getbalance)
   while ( $balance < $meta | bc)
     do
       echo $balance
       bitcoin-cli "-rpcwallet=$wallet" generatetoaddress 1 "$address"
     ((balance++))
   done
}

function generarbloques2
{
   echo "Ingrese cuantos bloque desea minar:"
     read bloques
   echo "Ingrese la wallet que va a usar para recibir:"
     read wallet
   echo "Ingrese la dirección para recibir la recompensa:"
     read address
   bitcoin-cli "-rpcwallet=$wallet" generatetoaddress $bloques "$address"
   balance=$(bitcoin-cli "-rpcwallet=$wallet" getbalance)
   echo "El nuevo balance de la wallet $wallet es:"
   echo "$balance"
}

function txs {
   echo "#### Bienvenido al asistente de generación de transacciones de bitcoin ####"
   echo "Ingrese el nombre de la wallet que desea usar:"
     read name_wallet
   echo "Ingrese la dirección que va a recibir:"
     read address
   echo "Ingrese la cantidad a enviar:"
     read cantidad
   bitcoin-cli "-rpcwallet=$name_wallet" sendtoaddress $address $cantidad
}

function resumentx {
   echo "Ingrese el ID de la transacción a consultar:"
     read ID
   echo "Ingrese la wallet a consultar:"
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

#if downloads; then
#   echo "######### La descarga de los binarios fue exitosa. #########"
#else
#   echo "######### Falló la descarga #########"
#fi

#### Las siguientes líneas verifican los archivos descargados ############### 

#if verification; then
#   echo "######### Verificación exitosa de la firma binaria #########"
#else
#   echo "######### Falló la verificación #########"
#fi

#### Las siguientes líneas instalan BITCOIN CORE ########################### 

#if installation; then
#   echo "######### La instalación ha sido exitosa #########"
#else
#   echo "######### La instalación ha fallado #########"
#fi

#### Las siguientes líneas configuran BITCOIN CORE en modo REGTEST ######## 

#if configuration; then
#   echo "######### La configuración fue exitosa #########"
#else
#   echo "######### Falló la configuración #########"
#fi

#### ===============> INICIO DE BITCOIND EN MODO DAEMON <=================== ####

#bitcoind -daemon

#### =============> CREACIÓN DE WALLETS, DIRECCIONES Y TXS <================= ####

#createwallet

#createaddress

#generarbloques

#### Para generar los bloques trabaja mejor esta función, "generarbloques" no me funcionó :( ####
#generarbloques2

#### En una prueba me tomó más de 11000 bloques obtener 22 bitcoins y pienso que se comporta de esa ###
### manera debido a que simula las probabilidades de obtener un bloque ###############################
### En un segundo intento tomó alrededor de 2500 bloquea obtener 20 bitcoins
 
#txs

#### Consulta el estado de la mempool para ver la transacción en espera. ####
#bitcoin-cli getrawmempool

#### Genera un nuevo bloque para minar la transacción. ####
#bitcoin-cli "-rpcwallet=Miner" generatetoaddress 1 "bcrt1qvam7knlttshee8qckqaqxcn8309tfzdv7nsmw7"

#resumentx
