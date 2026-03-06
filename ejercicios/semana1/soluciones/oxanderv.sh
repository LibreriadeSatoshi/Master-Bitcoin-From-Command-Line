#!/bin/bash

# Sube un archivo como este mediante un pull request en la carpeta soluciones, el archivo debe tener tu nombre en discord

# Nombre de archivos, rutas y comandos

BitcoinCorePath="../../../../bitcoin-30.2-x86_64-linux-gnu.tar.gz"
BitcoinCoreNameFile="bitcoin-30.2-x86_64-linux-gnu.tar.gz"
UncompressPath="../../../../bitcoin-30.2"
CHECKSUMS="../../../../SHA256SUMS"
bitcoind="../../../../bitcoin-30.2/bin/bitcoind"
BitConf="../../../../bitcoin-30.2/.bitcoin/bitcoin.conf" # Ruta relativa a bitcoin.conf
BitConf_ABS=$(realpath "$BitConf") # Ruta absoluta a bitcoin.conf
bitcoinCli="../../../../bitcoin-30.2/bin/bitcoin-cli"


# Verificar que los archivos existen
if [[ ! -f "$BitcoinCorePath" ]]; then
    echo "Error: No se encontró $BitcoinCorePath"
    sleep 1
    echo "Descargando Bitcoin-core ...."
    sleep 1
    wget https://bitcoincore.org/bin/bitcoin-core-30.2/bitcoin-30.2-x86_64-linux-gnu.tar.gz -O $BitcoinCorePath
else   
    echo "Archivo $BitcoinCorePath ya existe"
    sleep 1
fi

if [[ ! -f "$CHECKSUMS" ]]; then
    echo "Error: No se encontró $CHECKSUMS"
    sleep 1
    echo "Descargando SHA256SUMS ...."
    sleep 1
    wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS -O $CHECKSUMS
else
    echo "Archivo $CHECKSUMS ya existe"
    sleep 1
fi

# Método 1: Verificar directamente con sha256sum
echo "Verificando hash de $BitcoinCorePath ..."
sleep 1
# Calcular el hash del archivo descargado
HASH_CALCULADO=$(sha256sum "$BitcoinCorePath" | awk '{print $1}')
# Buscar el hash esperado del archivo SHA256SUMS
HASH_ESPERADO=$(grep "$BitcoinCoreNameFile" "$CHECKSUMS" | awk '{print $1}')

# Condicion para comparar el hash calculado con el esperado
if [[ "$HASH_CALCULADO" == "$HASH_ESPERADO" ]]; then
    echo "✅ VERIFICACIÓN EXITOSA: Los hashes coinciden"
    sleep 1
    echo "Se puede proceder con la instalación"
    sleep 1
    # Consulta si el archivo ya fue descomprimido
    if [[ ! -d "$UncompressPath" ]]; then
        echo "Descomprimiendo $BitcoinCorePath ..."
        sleep 1
        tar -xvf "$BitcoinCorePath" -C ../../../../ # Se descomprime en la ubicacion donde se encuentra el archivo BitcoinCore
    else
        echo "Archivo $UncompressPath ya esta descomprimido"
        sleep 1
    fi
else
    echo "❌ ERROR: Los hashes no coinciden"
    sleep 1
    echo "  Calculado: $HASH_CALCULADO"
    echo "  Esperado:  $HASH_ESPERADO"
    exit 1
fi

if [[ ! -f "$BitConf" ]]; then
    echo "Error: No se encontró $BitConf"
    sleep 1
    echo "Creando archivo de configuracion bitcoin.conf..."
    sleep 1
    mkdir -p "$UncompressPath"/.bitcoin
    echo "regtest=1" >> $BitConf
    echo "fallbackfee=0.0001" >> $BitConf
    echo "server=1" >> $BitConf
    echo "txindex=1" >> $BitConf
    echo "Archivo bitcoin.conf creado correctamente !!!"
    sleep 1
else
    echo "Archivo $BitConf ya existe"
    sleep 1
fi

# Fin del script
echo "Validando version de Bitcoin Core ..."
sleep 1
$bitcoind --version

sleep 3
echo "Todos los procesos se completaron correctamente"
sleep 2
echo "Calentando las calderas para ejecutar Bitcoin Core ..."
sleep 2
echo "Cinturones abrochados..."
sleep 2 
echo "¡Despegue programado para Bitcoin Core! en ..."
sleep 2
echo "3..."
sleep 1
echo "2..."
sleep 1
echo "1..."
sleep 1
echo "Ignicion !!!!"
sleep 1
# Ejecutar Bitcoin Core con la configuración personalizada
# $bitcoind -conf="$BitConf_ABS" -printtoconsole # Con este comando se visualizan los procesos en tiempo real
$bitcoind -regtest -conf="$BitConf_ABS" -daemon # Con este comando se ejecuta en segundo plano

# Creacion de wallets
echo "Creando wallets..."
sleep 1
if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Miner" 2>/dev/null; then
    echo "Wallet 'Miner' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Miner"
else
    echo "Wallet 'Miner' creada exitosamente"
fi

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Trader" 2>/dev/null; then
    echo "Wallet 'Trader' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Trader"
else
    echo "Wallet 'Trader' creada exitosamente"
fi


# Creando direccion para minero
AddressMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
echo "Direccion del Miner: $AddressMiner"

while [ "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance 2>/dev/null | cut -d. -f1)" -eq 0 ]; do
    echo "Esperando que el Miner reciba la recompensa..."
    echo "Minando bloques..."
    # Generacion del bloque, el proceso de mineria apunta a la direccion del minero
    $bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 101 $AddressMiner
    sleep 1
    
done
# COMENTARIOS:
# - El proceso de minería requirío de apenas 1 bloque para que el saldo del Minero fuera positivo en 50 monedas
# - El comportamiento actual respecto a la recompensa por bloque es debido al hecho que la cadena es muy joven
#   la recompensa por bloque se reduce cada 210,000 bloques (halving) y como esta cadena aun no ha alcanzado
#   ese numero de bloques, la recompensa sigue siendo de 50 monedas.

echo "Minero recibio la recompensa"
# Consulta el saldo de la billetera Miner
saldo=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
# Se imprime el saldo de la billetera Miner
echo "Saldo del Miner: $saldo"
sleep 1

# Crear una dirección receptora con la etiqueta "Recibido" desde la billetera Trader
AddressTrader=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Trader" getnewaddress "Recibido")
echo "Direccion del Trader: $AddressTrader"

# Miner paga 20 monedas a Trader
echo "Minero paga 20 monedas a Trader"
txid=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" sendtoaddress $AddressTrader 20)
echo "Transaccion: $txid"
sleep 1

# Consulta el estado de la transaccion en la mempool
echo "Consultando el estado de la transaccion en la mempool..."
mempool=$($bitcoinCli -conf="$BitConf_ABS" -regtest getmempoolentry $txid)
echo "Mempool: $mempool"
sleep 1

# Minar un bloque para confirmar la transaccion
echo "Minando un bloque para confirmar la transaccion..."
blockhash=$($bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 $AddressMiner | jq -r '.[0]')
echo "Blockhash: $blockhash"
sleep 1

# Consultar informacion de la transaccion despues de minar el bloque
echo "Consultando informacion de la transaccion despues de minar el bloque..."
txinfo=$($bitcoinCli -conf="$BitConf_ABS" -regtest getrawtransaction $txid 2)
echo "Transaccion: $txinfo"
sleep 1

# Extraer cada valor
# Cantidad de entrada
echo "Cantidad de entrada"
INPUT_VALUE=$(echo "$txinfo" | jq -r '.vin[0].prevout.value')
echo "Input (prevout): $INPUT_VALUE"
sleep 1

# Valor enviado al trader
OUTPUT_TRADER=$(echo "$txinfo" | jq -r --arg addr "$AddressTrader" '.vout[] | select(.scriptPubKey.address == $addr) | .value')
echo "Cantidad enviada a Trader: $OUTPUT_TRADER"

# Valor del cambio (cualquier dirección que NO sea la del trader)
OUTPUT_CAMBIO=$(echo "$txinfo" | jq -r --arg addr "$AddressTrader" '.vout[] | select(.scriptPubKey.address != $addr) | .value')
echo "Cantidad de cambio: $OUTPUT_CAMBIO"

# Cantidad pagada en comisiones
FEE=$(echo "$txinfo" | jq -r '.fee')
echo "Cantidad pagada en comisiones Fee: $FEE"
sleep 1

# Consulta altura del bloque
height=$($bitcoinCli -conf="$BitConf_ABS" -regtest getblockheader "$blockhash" | jq -r '.height')
echo "Altura del bloque: $height"

# Consultar el saldo de la billetera Miner
echo "Consultando el saldo de la billetera Miner despues de minar el bloque..."
saldoMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
echo "Saldo del Miner: $saldoMiner"
sleep 1

# Consultar el saldo de la billetera Trader
echo "Consultando el saldo de la billetera Trader despues de minar el bloque..."
saldoTrader=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Trader" getbalance)
echo "Saldo del Trader: $saldoTrader"
sleep 1