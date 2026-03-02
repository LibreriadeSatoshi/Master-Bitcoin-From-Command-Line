#!/bin/bash

#### Configuración
# 1. Descargar los binarios principales de Bitcoin
wget https://bitcoincore.org/bin/bitcoin-core-30.2/bitcoin-30.2-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS
wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS.asc

# 2. Verificar la integridad de los binarios
# importar las claves GPG de los desarrolladores de Bitcoin Core
git clone https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/*
# verificar la firma GPG del archivo SHA256SUMS
gpg --verify SHA256SUMS.asc
if [ $? -eq 0 ]; then
    echo "Firma GPG verificada correctamente"
else
    exit 1
fi
# verificar la suma SHA256 de los binarios descargados
sha256sum --ignore-missing --check SHA256SUMS
if [ $? -eq 0 ]; then
    echo "Verificación exitosa de la firma binaria"
else
    exit 1
fi

tar -xzf bitcoin-30.2-x86_64-linux-gnu.tar.gz

#### Inicio
# 1. crear bitcoin.conf
mkdir -p ~/.bitcoin
cat > ~/.bitcoin/bitcoin.conf <<EOF
regtest=1
server=1
txindex=1
fallbackfee=0.0001
rpcuser=usuario
rpcpassword=contraseña
EOF
export PATH="$PWD/bitcoin-30.2/bin:$PATH"

# 2. Iniciar `bitcoind -daemon`.
./bitcoin-30.2/bin/bitcoind -daemon
sleep 3

# 3. Crear dos billeteras llamadas `Miner` y `Trader`.
alias bitcoin-cli="bitcoin-30.2/bin/bitcoin-cli -regtest -rpcuser=usuario -rpcpassword=contraseña"
bitcoin-cli createwallet Miner
bitcoin-cli createwallet Trader

# 4. Generar una dirección desde la billetera `Miner` con una etiqueta "Recompensa de Mineria".
bitcoin-cli loadwallet Miner
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "Dirección de Minería: $miner_address"

# 5. Extraer nuevos bloques a esta dirección hasta obtener un saldo de billetera positivo.
bitcoin-cli generatetoaddress 101 "$miner_address"

#6. Escribir un breve comentario que describa por qué el saldo de la billetera para las recompensas en bloque se comporta de esa manera.
# El saldo de la billetera se comporta así porque cada bloque minado genera una recompensa de 50 BTC (en regtest, esta cantidad puede ser ajustada). La billetera `Miner` recibe esta recompensa y el saldo aumenta con cada bloque generado.

# 7. Imprimir el saldo de la billetera `Miner`.
balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Saldo de la billetera Miner: $balance BTC"

#### Uso
# 1. Crear una dirección receptora con la etiqueta "Recibido" desde la billetera `Trader`.
bitcoin-cli loadwallet Trader
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido")
echo "Dirección de Trader: $trader_address"

# 2. Enviar una transacción que pague 20 BTC desde la billetera `Miner` a la billetera del `Trader`.
txid=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $trader_address 20)
echo "Transacción enviada con ID: $txid"

# 3. Obtener la transacción no confirmada desde el "mempool" del nodo y mostrar el resultado. (pista: `bitcoin-cli help` para encontrar la lista de todos los comandos, busca `getmempoolentry`).
mempool_entry=$(bitcoin-cli getmempoolentry $txid)
echo "Entrada del mempool para la transacción $txid: $mempool_entry"

# 4. Confirmar la transacción creando 1 bloque adicional.
bitcoin-cli generatetoaddress 1 $miner_address > /dev/null
echo "Bloque adicional generado para confirmar la transacción"

# 5. Obtener los siguientes detalles de la transacción y mostrarlos en la terminal:
# - `txid:` `<ID de la transacción>`
echo "Transacción enviada con ID: $txid"
# - `<De, Cantidad>`: `<Dirección del Miner>`, `Cantidad de entrada.`
tx=$(bitcoin-cli -rpcwallet=Miner getrawtransaction $txid true)
inputs=$(echo $tx | jq -r '.vin[] | "\(.txid):\(.vout)"')
echo "Entradas de la transacción:"
input_sum=0
while read -r input; do
    txid_input=$(echo $input | cut -d: -f1)
    vout_input=$(echo $input | cut -d: -f2)
    echo "  TxID: $txid_input Vout: $vout_input"
    input_tx=$(bitcoin-cli getrawtransaction $txid_input true)
    input_details=$(echo $input_tx | jq -r ".vout[] | select(.n == $vout_input) | \"\(.scriptPubKey.address) \(.value) BTC\"")
    echo "  $input_details"
    # Acumular el valor de las inputs
    val=$(echo $input_tx | jq -r ".vout[] | select(.n == $vout_input) | .value")          
    input_sum=$(echo "$input_sum + $val" | bc)
done <<< "$inputs"
# - `<Enviar, Cantidad>`: `<Dirección del Trader>`, `Cantidad enviada.`
outputs=$(echo $tx | jq -r '.vout[] | "\(.scriptPubKey.address):\(.value)"')
echo "Salidas de la transacción:"
output_sum=0
while read -r output; do
    address_output=$(echo $output | cut -d: -f1)
    value_output=$(echo $output | cut -d: -f2)
    echo "  $address_output $value_output BTC"
    # Acumular el valor de las outputs
    output_sum=$(echo "$output_sum + $value_output" | bc)
done <<< "$outputs"
# - `<Cambio, Cantidad>`: `<Dirección del Miner>`, `Cantidad de cambio.`
change_address=$(echo $tx | jq -r '.vout[] | select(.value != 20) | .scriptPubKey.address')
change_value=$(echo $tx | jq -r '.vout[] | select(.value != 20) | .value')
echo "Cambio: $change_address, $change_value BTC"
# - `Comisiones`: `Cantidad pagada en comisiones.`
fee=$(echo "scale=8; $input_sum - $output_sum" | bc)
echo "Comisiones pagadas: $fee BTC"
# - `Bloque`: `Altura del bloque en el que se confirmó la transacción.`
block_hash=$(echo $tx | jq -r '.blockhash')
block_height=$(bitcoin-cli getblockheader $block_hash true | jq -r '.height')
echo "Altura del bloque donde se confirmó la transacción: $block_height"
# - `Saldo de Miner`: `Saldo de la billetera Miner después de la transacción.`
balance_after=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Saldo de la billetera Miner después de la transacción: $balance_after BTC"
# - `Saldo de Trader`: `Saldo de la billetera Trader después de la transacción.`
balance_trader=$(bitcoin-cli -rpcwallet=Trader getbalance)
echo "Saldo de la billetera Trader después de la transacción: $balance_trader BTC"

bitcoin-cli stop