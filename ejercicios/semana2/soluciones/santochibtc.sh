#!/bin/bash

#### Configuración
# Descargar los binarios principales de Bitcoin
#wget https://bitcoincore.org/bin/bitcoin-core-30.2/bitcoin-30.2-x86_64-linux-gnu.tar.gz
#wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS
#wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS.asc

# Verificar la integridad de los binarios
# importar las claves GPG de los desarrolladores de Bitcoin Core
#git clone https://github.com/bitcoin-core/guix.sigs
#gpg --import guix.sigs/builder-keys/*
#rm -rf guix.sigs
# verificar la firma GPG del archivo SHA256SUMS
#gpg --verify SHA256SUMS.asc
if [ $? -eq 0 ]; then
    echo "Firma GPG verificada correctamente"
else
    exit 1
fi
# verificar la suma SHA256 de los binarios descargados
#sha256sum --ignore-missing --check SHA256SUMS
if [ $? -eq 0 ]; then
    echo "Verificación exitosa de la firma binaria"
else
    exit 1
fi

#tar -xzf bitcoin-30.2-x86_64-linux-gnu.tar.gz
#rm bitcoin-30.2-x86_64-linux-gnu.tar.gz SHA256SUMS SHA256SUMS.asc

#### Inicio
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
./bitcoin-30.2/bin/bitcoind -daemon
sleep 3

# 1. Crear dos billeteras llamadas `Miner` y `Trader`.
alias bitcoin-cli="bitcoin-30.2/bin/bitcoin-cli -regtest -rpcuser=usuario -rpcpassword=contraseña"
bitcoin-cli createwallet Miner
bitcoin-cli createwallet Trader

# 2. Fondear la billetera `Miner`
bitcoin-cli loadwallet Miner
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "Dirección de Minería: $miner_address"
bitcoin-cli generatetoaddress 101 "$miner_address" > /dev/null

#3. Crear una transacción desde `Miner` a `Trader` (llamémosla la transacción `parent`):
bitcoin-cli loadwallet Trader
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress "parent")
utxos=$(bitcoin-cli -rpcwallet=Miner listunspent 1)
# seleccionar dos uxtos de 50 BTC
utxos=$(bitcoin-cli -rpcwallet=Miner listunspent | jq '[.[] | select(.amount == 50)] | .[0:2]')
inputs=$(echo $utxos | jq -c '[.[] | {txid: .txid, vout: .vout}]')
# obtener una dirección de cambio para el `Miner`
miner_change_address=$(bitcoin-cli -rpcwallet=Miner getrawchangeaddress)
fee=$(echo "scale=8; 1000/100000000" | bc)
# crear la tx 'parent'
change_amount=$(echo "scale=8; 30 - $fee" | bc)
parent_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "$inputs" "[{ \"$trader_address\": 70 }, { \"$miner_change_address\": $change_amount }]")

# 4. Firmar y transmitir la transacción `parent`
signed_parent_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $parent_tx)
txid=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $(echo $signed_parent_tx | jq -r '.hex'))
echo "Transacción parent enviada con ID: $txid"

# 5. Realizar consultas al "mempool" del nodo para obtener los detalles de la transacción `parent`. Utiliza los detalles para crear una variable JSON
raw_tx=$(bitcoin-cli getrawtransaction $txid true)
mempool_entry=$(bitcoin-cli getmempoolentry $txid)

json="{\"input\": ["
is_first=true
while read -r utxo; do
    if [ "$is_first" = true ]; then
        is_first=false
    else
        json="$json,"
    fi
    txid_input=$(echo $utxo | cut -d: -f1)
    vout_input=$(echo $utxo | cut -d: -f2)
    json="$json{\"txid\": \"$txid_input\", \"vout\": $vout_input}"
done <<< "$(echo $raw_tx | jq -r '.vin[] | "\(.txid):\(.vout)"')"
json="$json],\"output\": ["
is_first=true
while read -r output; do
    if [ "$is_first" = true ]; then
        is_first=false
    else
        json="$json,"
    fi
    address=$(echo $output | jq -r '.scriptPubKey.address')
    amount=$(echo $output | jq -r '.value')
    json="$json{\"address\": \"$address\", \"amount\": $amount}"
done <<< "$(echo $raw_tx | jq -c '.vout[]')"
json="$json\"fee\": $(echo $mempool_entry | jq -r '.fees.base'), \"weight\": $(echo $mempool_entry | jq -r '.weight')}"
# 6. Imprime el JSON anterior en la terminal.
echo "Variable JSON creada: $json"
# 7. Crea una nueva transmisión que gaste la transacción anterior (`parent`).
new_miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "child")
child_tx=$(bitcoin-cli -rpcwallet=Trader createrawtransaction "[{\"txid\": \"$txid\", \"vout\": 1}]" "[{\"$new_miner_address\": 29.99998}]")
signed_child_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $child_tx)
child_txid=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $(echo $signed_child_tx | jq -r '.hex'))
# 8. Realiza una consulta `getmempoolentry` para la tranasacción `child` y muestra la salida.
bitcoin-cli getmempoolentry $child_txid

# 9. Ahora, aumenta la tarifa de la transacción `parent` utilizando RBF.
new_miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "child")
fee=$(echo "scale=8; 10000/100000000" | bc)
# crear la tx 'parent'
change_amount=$(echo "scale=8; 100 - $fee" | bc)
parent2_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "$inputs" "[{ \"$miner_change_address\": $change_amount }]")

# 10. Firma y transmite la nueva transacción principal.
signed_parent2_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $parent2_tx)
parent2_txid=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $(echo $signed_parent2_tx | jq -r '.hex'))

# 11. Realiza otra consulta `getmempoolentry` para la transacción `child`
bitcoin-cli getmempoolentry $child_txid

# 12. Imprime una explicación en la terminal de lo que cambió
echo "La transacción 'child' ya no está en la mempool porque"
echo "la transacción 'parent' fue reemplazada por una nueva"
echo "transacción con una tarifa más alta. El utxo que gastaba"
echo "la transacción 'child' ya no existe."

bitcoin-cli stop