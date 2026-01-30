MINERWALLET=Miner2
TRADERWALLET=Trader2


#Creating wallets
bitcoin-cli -named createwallet wallet_name=$MINERWALLET passphrase=Contraseña.1
bitcoin-cli -named createwallet wallet_name=$TRADERWALLET passphrase=Contraseña.1

bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 120

minerAddress=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "Recompensa de Mineria")

bitcoin-cli generatetoaddress 103 "$minerAddress"

#Get current balance from Miner
balance=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
echo "Current balance of Miner wallet: $balance"


# Obtener todos los UTXOs de la billetera
utxos=$(bitcoin-cli -rpcwallet=$MINERWALLET listunspent)

echo $utxos


# Extraer los txid y vout de las recompensas en bloque
input1_txid=$(echo "$utxos" | jq -r '.[0].txid')  # Primer UTXO
input1_vout=$(echo "$utxos" | jq -r '.[0].vout')  # Primer UTXO

input2_txid=$(echo "$utxos" | jq -r '.[1].txid')  # Segundo UTXO
input2_vout=$(echo "$utxos" | jq -r '.[1].vout')  # Segundo UTXO

echo "Input 1: $input1_txid $input1_vout"
echo "Input 2: $input2_txid $input2_vout"

# Crear una dirección receptora con la etiqueta "Recibido" desde la billetera Trader.
traderAddress=$(bitcoin-cli -rpcwallet=$TRADERWALLET getnewaddress "Recibido")
echo "Dirección de cambio del trader RECIBIDO: $traderAddress"

minerCambio=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "CambioMiner")
echo "Dirección de cambio del Miner: $minerCambio"

# Create the raw transaction (parent)
echo "Creando la transacción parent con RBF habilitado..."
raw_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET createrawtransaction \
  "[{\"txid\": \"$input1_txid\", \"vout\": $input1_vout, \"sequence\": 0}, {\"txid\": \"$input2_txid\", \"vout\": $input2_vout, \"sequence\": 0}]" \
  "{\"${traderAddress}\": 70, \"${minerCambio}\": 29.99999}" \
 0 true)

# Firmar la transacción
signed_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_tx" | jq -r .hex)

# Enviar la transacción
txid=$(bitcoin-cli -rpcwallet=$MINERWALLET sendrawtransaction "$signed_tx")

# Mostrar el TXID de la transacción
echo "Transaction sent with TXID: $txid"

mempool_txid=$(bitcoin-cli getmempoolentry "$txid")

 


 # Obtener el script_pubkey de las direcciones
miner_script_pubkey=$(bitcoin-cli -rpcwallet=$MINERWALLET getaddressinfo "$minerCambio" | jq -r .scriptPubKey)
trader_script_pubkey=$(bitcoin-cli -rpcwallet=$TRADERWALLET getaddressinfo "$traderAddress" | jq -r .scriptPubKey)

# Obtener la tarifa de la transacción
# Para calcular la tarifa, primero necesitas obtener el tamaño de la transacción en bytes
tx_size=$(bitcoin-cli -rpcwallet=$MINERWALLET getrawtransaction "$txid" 1 | jq -r .size)
# Supongamos que la tarifa es de 1 satoshi por byte (ajusta según sea necesario)
fee=$((tx_size * 1))

# Obtener el peso de la transacción en vbytes
tx_weight=$(bitcoin-cli -rpcwallet=$MINERWALLET getmempoolentry "$txid" | jq -r .weight)

# Construir el JSON
json_output=$(jq -n \
  --arg txid1 "$input1_txid" \
  --arg vout1 "$input1_vout" \
  --arg txid2 "$input2_txid" \
  --arg vout2 "$input2_vout" \
  --arg miner_script_pubkey "$miner_script_pubkey" \
  --arg miner_amount "29.99999" \
  --arg trader_script_pubkey "$trader_script_pubkey" \
  --arg trader_amount "70" \
  --arg fee "$fee" \
  --arg tx_weight "$tx_weight" \
  '{
    input: [
      { txid: $txid1, vout: $vout1 },
      { txid: $txid2, vout: $vout2 }
    ],
    output: [
      { script_pubkey: $miner_script_pubkey, amount: $miner_amount },
      { script_pubkey: $trader_script_pubkey, amount: $trader_amount }
    ],
    Fees: $fee,
    Weight: $tx_weight
  }'
)

# Mostrar el JSON
echo "$json_output"




decoded_parent_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET decoderawtransaction "$signed_tx")

child_vout=$(echo "$decoded_parent_tx" | jq -r ".vout[] | select(.scriptPubKey.address==\"$minerCambio\") | .n")


# Crear nueva dirección para Miner para la salida de la transacción child
minerAddress2=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "Nueva dir ex2")
echo "Nueva dirección miner ex2: $minerAddress2"


# Crear transaccion hija
raw_tx_child=$(bitcoin-cli -rpcwallet=$MINERWALLET createrawtransaction \
  "[{\"txid\": \"$txid\", \"vout\": $child_vout}]" \
  "{\"${minerAddress2}\": 29.99998}" \
)

echo "raw_tx_child: $raw_tx_child"

# Firmar transaccion hija
signed_child_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_tx_child" | jq -r '.hex')

child_txid=$(bitcoin-cli -rpcwallet=$MINERWALLET sendrawtransaction "$signed_child_tx")

echo "Child transaction sent with TXID: $child_txid"

#Ver info de mempool
bitcoin-cli -rpcwallet=$MINERWALLET getmempoolentry "$child_txid"

#Creando transaccion conflictiva
# Crear transaccion hija2
raw_tx_child2=$(bitcoin-cli -rpcwallet=$MINERWALLET createrawtransaction \
  "[{\"txid\": \"$txid\", \"vout\": $child_vout}]" \
  "{\"${minerAddress2}\": 29.99988}" \
)

# Firmar transaccion hija
signed_child_tx2=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_tx_child2" | jq -r '.hex')

child_txid2=$(bitcoin-cli -rpcwallet=$MINERWALLET sendrawtransaction "$signed_child_tx")


#Ver info de mempool
bitcoin-cli -rpcwallet=$MINERWALLET getmempoolentry "$child_txid2"


# En este proceso, se crean dos transacciones que intentan gastar el mismo vout de una transacción anterior. 
# La primera transacción (child_txid) se firma y se envía al mempool, donde se puede consultar su información, 
# como la comisión y el tamaño. Luego, se crea una segunda transacción (child_txid2) que también intenta gastar el mismo vout. 
# Sin embargo, Bitcoin Core no permite que ambas transacciones coexistan en el mempool. 
# Si la segunda transacción tiene una comisión más alta, reemplazará a la primera gracias a la función 
# Replace-By-Fee (RBF); si no, será rechazada. Al consultar el mempool, se puede verificar cuál de las dos transacciones está 
# presente y si alguna fue reemplazada o rechazada, lo que se puede confirmar con mensajes de error o listando las transacciones en el mempool.





