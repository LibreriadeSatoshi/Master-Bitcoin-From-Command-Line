#!/bin/bash

# Lista de URLs a descargar
URLS=(
    "https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz"
    "https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS"
    "https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS.asc"
)

# Descargar cada archivo en la lista
for url in "${URLS[@]}"; do
    output_file=$(basename "$url")
    echo "Descargando el archivo desde $url..."
    curl -o "$output_file" "$url"

    # Verificar si la descarga fue exitosa
    if [ $? -eq 0 ]; then
        echo "Descarga completada: $output_file"
    else
        echo "Error al descargar el archivo: $output_file"
        exit 1
    fi
done

# Verificar la integridad del archivo descargado
echo "Verificando la integridad del archivo descargado..."
sha256sum --check SHA256SUMS --ignore-missing
if [ $? -eq 0 ]; then
    echo "La verificación de integridad fue exitosa."
else
    echo "Error en la verificación de integridad. El archivo puede estar corrupto."
    exit 1
fi


# Descargar las firmas PGP desde el repositorio de GitHub
[ -d "guix.sigs" ] || git clone https://github.com/bitcoin-core/guix.sigs

#Importando las claves PGP de los constructores en mi llavero.
gpg --import "guix.sigs/builder-keys/"*

# Verificar la firma del archivo descargado
echo "Verificando la firma del archivo descargado..."
gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -q "Good signature" && echo "Verificación exitosa de la firma binaria" || { echo "No se encontraron firmas válidas."; exit 1; }


#descomprimiendo e instalando binarios
tar -zxvf bitcoin-29.0-x86_64-linux-gnu.tar.gz 
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*

# Crear el archivo de configuración .bitcoin
echo "Creando el archivo de configuración .bitcoin..."
cat <<EOF > .bitcoin/bitcoin.conf
# Configuración de Bitcoin Core
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

echo "Archivo .bitcoin creado exitosamente."

# Mensaje de inicio
echo "Iniciando nodo..."

# Comprobar si el nodo ya está en ejecución
if pgrep -x "bitcoind" > /dev/null; then
    echo "El nodo ya está en ejecución."
else
    # Iniciar el nodo en segundo plano
    bitcoind -daemon
    sleep 5

    echo "Nodo iniciado."
fi


MINERWALLET=Miner5
TRADERWALLET=Trader5


#Creating wallets
bitcoin-cli -named createwallet wallet_name=$MINERWALLET passphrase=Contraseña.1
bitcoin-cli -named createwallet wallet_name=$TRADERWALLET passphrase=Contraseña.1

#Creating Miner transaction 

minerAddress=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "Recompensa de Mineria")

echo "Miner Address is: $minerAddress"

#Get current balance from Miner
balance=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
echo "Current balance of Miner wallet: $balance"

# Generar bloques hasta que el balance sea mayor a 0
blocks_generated=0
while [ "$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)" == "0.00000000" ]; do
    bitcoin-cli generatetoaddress 1 "$minerAddress"
    blocks_generated=$((blocks_generated + 1))
done

# Mostrar el balance final y la cantidad de bloques generados
final_balance=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
echo "Balance final de la billetera Miner: $final_balance"
echo "Cantidad de bloques generados: $blocks_generated"

echo "#La recompensa es gastable es madurada luego de 100 bloques siguientes. En este caso miné 101 bloques, la recompensa de 50 BTC bloques es madura, así que es gastable."


# 1. Crear una dirección receptora con la etiqueta "Recibido" desde la billetera Trader.
traderAddress=$(bitcoin-cli -rpcwallet=$TRADERWALLET getnewaddress "Recibido")
echo "Dirección de cambio del trader RECIBIDO: $traderAddress"

# 2. Enviar una transacción que pague 20 BTC desde la billetera Miner a la billetera del Trader.

#Direccion de cambio
minerCambio=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "CambioMiner")
echo "Dirección de cambio del Miner: $minerCambio"

# Obtener la transacción no confirmada desde el "mempool" del nodo y mostrar el resultado. (pista: bitcoin-cli help para encontrar la lista de todos los comandos, busca getmempoolentry).

# Listar los UTXOs no gastados y tomar el primer elemento
utxos=$(bitcoin-cli -rpcwallet=$MINERWALLET listunspent 1 9999999 | jq '.[0]')

# Extraer el txid y vout
txid=$(echo $utxos | jq -r '.txid')
vout=$(echo $utxos | jq -r '.vout')

# Imprimir los resultados
echo "TXID: $txid"
echo "VOUT: $vout"


raw_transactionHex=$(bitcoin-cli createrawtransaction \
'[{"txid": "'"$txid"'", "vout": '"$vout"'}]' \
'[{"'"$traderAddress"'": 20}, {"'"$minerCambio"'": 29.99999000}]')


bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 120
firmadotx=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_transactionHex" | jq -r '.hex')

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$firmadotx")

echo "TxID de la transacción enviada: $txidEnviada"


# Confirmar la transacción creando 1 bloque adicional.
bitcoin-cli generatetoaddress 1 "$traderAddress"



bitcoin-cli -rpcwallet=$MINERWALLET gettransaction "$txidEnviada"



# Obtener los siguientes detalles de la transacción y mostrarlos en la terminal:
# txid: <ID de la transacción>
# <De, Cantidad>: <Dirección del Miner>, Cantidad de entrada.
# <Enviar, Cantidad>: <Dirección del Trader>, Cantidad enviada.
# <Cambio, Cantidad>: <Dirección del Miner>, Cantidad de cambio.
# Comisiones: Cantidad pagada en comisiones.
# Bloque: Altura del bloque en el que se confirmó la transacción.
# Saldo de Miner: Saldo de la billetera Miner después de la transacción.
# Saldo de Trader: Saldo de la billetera Trader después de la transacción.

#!/bin/bash

# Definir las variables

# Obtener información de la transacción
tx_info=$(bitcoin-cli -rpcwallet="$MINERWALLET" gettransaction "$txidEnviada")

# Extraer detalles de la transacción
txid=$(echo "$tx_info" | jq -r '.txid')
amount=$(echo "$tx_info" | jq -r '.amount')
fee=$(echo "$tx_info" | jq -r '.fee')
confirmations=$(echo "$tx_info" | jq -r '.confirmations')
blockhash=$(echo "$tx_info" | jq -r '.blockhash')
time=$(echo "$tx_info" | jq -r '.time')

# Aquí se asume que tienes las direcciones y cantidades
# Debes reemplazar estas variables con los valores reales
change_amount=0.00000000  # Cantidad de cambio (ajusta según sea necesario)

# Mostrar los detalles de la transacción
echo "Detalles de la transacción:"
echo "txid: $txid"
echo "<De, Cantidad>: $miner_address, $amount"
echo "<Enviar, Cantidad>: $trader_address, $amount"
echo "<Cambio, Cantidad>: $minerCambio, $change_amount"
echo "Comisiones: $fee"
echo "Bloque: $blockhash (confirmaciones: $confirmations)"
echo "Saldo de Miner: $(bitcoin-cli -rpcwallet="$MINERWALLET" getbalance)"
echo "Saldo de Trader: $(bitcoin-cli -rpcwallet="$TRADERWALLET" getbalance)"
