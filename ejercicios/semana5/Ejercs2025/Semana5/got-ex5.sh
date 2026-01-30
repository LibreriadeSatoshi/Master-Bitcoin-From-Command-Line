MINERWALLET=MINER8
ALICEWALLET=ALICE8

bitcoin-cli -named createwallet wallet_name=$MINERWALLET passphrase=Contraseña.1
bitcoin-cli -named createwallet wallet_name=$ALICEWALLET passphrase=Contraseña.1

minerAddress=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "Recompensa de Mineria")
#Minando bloques
bitcoin-cli generatetoaddress 105 "$minerAddress"

#Balance para Miner
balance=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
echo "Balance - Miner wallet: $balance"

# Obtener todos los UTXOs de la billetera
utxos=$(bitcoin-cli -rpcwallet=$MINERWALLET listunspent)

echo $utxos
cantidad_utxos=$(echo "$utxos" | jq '. | length')
echo $cantidad_utxos


# Inicializar variables
total=0
inputs=()
cantidad_a_enviar=20


# Convertir el JSON a un array de líneas
txids=($(echo "$utxos" | jq -r '.[].txid'))
amounts=($(echo "$utxos" | jq -r '.[].amount'))
vouts=($(echo "$utxos" | jq -r '.[].vout'))

# Recorrer el array y asignar valores dentro del bucle
for i in "${!txids[@]}"; do
    txid="${txids[$i]}"
    amount="${amounts[$i]}"
    vout="${vouts[$i]}"
    
    echo "txid: $txid, amount: $amount, vout: $vout"

    # Agregar UTXO al JSON de inputs
    inputs+=("{\"txid\": \"$txid\", \"vout\": $vout, \"sequence\": 0}")
    
    
  #  echo "inputs: ${inputs[@]}"  # Mostrar el contenido del array
    # Sumar el total
    total=$(echo "$total + $amount" | bc)
    echo "Total: $total"
    
    # Verificar si hemos alcanzado la cantidad a enviar
    if (( $(echo "$total >= $cantidad_a_enviar" | bc -l) )); then
        break
    fi

done

# Convertir el array de inputs a un JSON válido
json_inputs=$(printf ',%s' "${inputs[@]}")
json_inputs="[${json_inputs:1}]"  # Eliminar la primera coma y agregar corchetes


echo "inputs final: $json_inputs"

# Crear direcciones receptoras con la etiqueta "Recibido" desde las billetreas.
alice_Address=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress "Recibido alice")
minerCambio_Address=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "CambioMiner")

# Definición de variables
fee=0.00001                # Ejemplo de fee

# Cálculo del cambio
cambio=$(echo "$total - $fee - $cantidad_a_enviar" | bc)

# Mostrar el resultado
echo "El cambio que debes dar es: $cambio"

echo "Creando la transacción"
raw_tx=$(bitcoin-cli -rpcwallet="$MINERWALLET" createrawtransaction "$json_inputs" \
    "{\"${alice_Address}\": $cantidad_a_enviar, \"${minerCambio_Address}\": $cambio}")


# Firmar la transacción
bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 120
signed_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_tx" | jq -r .hex)

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")

echo "TxID de la transacción enviada: $txidEnviada"

#Minando un bloque para confirmar transacciones.
bitcoin-cli generatetoaddress 1 "$minerAddress"


#Balance para Miner
balance_miner=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)

balance_alice=$(bitcoin-cli -rpcwallet=$ALICEWALLET getbalance)

echo "Balance - Miner wallet: $balance_miner"
echo "Balance - Alice wallet: $balance_alice"


#Crear una transacción en la que Alice pague 10 BTC al Miner, pero con un timelock relativo de 10 bloques.


# Obtener todos los UTXOs de la billetera
utxos=$(bitcoin-cli -rpcwallet=$ALICEWALLET listunspent)

echo $utxos
cantidad_utxos=$(echo "$utxos" | jq '. | length')
echo $cantidad_utxos


# Inicializar variables
total=0
inputs=()
cantidad_a_enviar=10


# Convertir el JSON a un array de líneas
txids=($(echo "$utxos" | jq -r '.[].txid'))
amounts=($(echo "$utxos" | jq -r '.[].amount'))
vouts=($(echo "$utxos" | jq -r '.[].vout'))

# Recorrer el array y asignar valores dentro del bucle
for i in "${!txids[@]}"; do
    txid="${txids[$i]}"
    amount="${amounts[$i]}"
    vout="${vouts[$i]}"
    
    echo "txid: $txid, amount: $amount, vout: $vout"

    # Agregar UTXO al JSON de inputs, con sequence=10 para aplicar el timelock relativo
    # Esto significa que la transacción no puede ser incluida en un bloque hasta que hayan pasado 10 bloques
    # desde que se creó la transacción.
    inputs+=("{\"txid\": \"$txid\", \"vout\": $vout, \"sequence\": 10}")
    
    
  #  echo "inputs: ${inputs[@]}"  # Mostrar el contenido del array
    # Sumar el total
    total=$(echo "$total + $amount" | bc)
    echo "Total: $total"
    
    # Verificar si hemos alcanzado la cantidad a enviar
    if (( $(echo "$total >= $cantidad_a_enviar" | bc -l) )); then
        break
    fi

done

# Convertir el array de inputs a un JSON válido
json_inputs=$(printf ',%s' "${inputs[@]}")
json_inputs="[${json_inputs:1}]"  # Eliminar la primera coma y agregar corchetes


echo "inputs final: $json_inputs"





# Crear direcciones receptoras con la etiqueta "Recibido" desde las billetreas.
aliceCambio_Address=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress "Recibido cambio alice")
miner_Address2=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "new address miner")

# Definición de variables
fee=0.00001                # Ejemplo de fee

# Cálculo del cambio
cambio=$(echo "$total - $fee - $cantidad_a_enviar" | bc)

# Mostrar el resultado
echo "El cambio que debes dar es: $cambio"

echo "Creando la transacción"
raw_tx=$(bitcoin-cli -rpcwallet="$ALICEWALLET" createrawtransaction "$json_inputs" \
    "{\"${miner_Address2}\": $cantidad_a_enviar, \"${aliceCambio_Address}\": $cambio}")



# Firmar la transacción
bitcoin-cli -rpcwallet=$ALICEWALLET walletpassphrase "Contraseña.1" 120
signed_tx=$(bitcoin-cli -rpcwallet=$ALICEWALLET signrawtransactionwithwallet "$raw_tx" | jq -r .hex)

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")


#Se obtiene error code: -26, error message: non-BIP68-final
#El error "non-BIP68-final" se produce porque la transacción intenta gastar entradas que 
#tienen restricciones de tiempo (como un timelock relativo) que no se han cumplido, 
#lo que significa que no se puede gastar hasta que se alcance el número de bloques especificado.

echo "TxID de la transacción enviada: $txidEnviada"


#Minando un bloque para confirmar transacciones.
bitcoin-cli generatetoaddress 10 "$minerAddress"

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")

echo "TxID de la transacción enviada: $txidEnviada"
#La transacción se envía correctamente después de minar 10 bloques, ya que el timelock relativo se ha cumplido.

#Balance para Miner
balance_miner=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)

balance_alice=$(bitcoin-cli -rpcwallet=$ALICEWALLET getbalance)

echo "Balance - Miner wallet: $balance_miner"
echo "Balance - Alice wallet: $balance_alice"