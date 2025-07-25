#1. Crea tres monederos: Miner, Empleado y Empleador.

MINERWALLET=MINERO
EMPLEADOWALLET=EMPLEADO
EMPLEADORWALLET=EMPLEADOR

#Creating wallets
bitcoin-cli -named createwallet wallet_name=$MINERWALLET passphrase=Contraseña.1

bitcoin-cli -named createwallet wallet_name=$EMPLEADOWALLET passphrase=Contraseña.2

bitcoin-cli -named createwallet wallet_name=$EMPLEADORWALLET passphrase=Contraseña.2


bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 1200
bitcoin-cli -rpcwallet=$EMPLEADOWALLET walletpassphrase "Contraseña.2" 1200
bitcoin-cli -rpcwallet=$EMPLEADORWALLET walletpassphrase "Contraseña.2" 1200


# 2. Fondea los monederos generando algunos bloques para Miner y enviando 80 BTC al Empleador.
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
cantidad_a_enviar=80


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
empleador_Address=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET getnewaddress "Recibido empleador")
minerCambio_Address=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "CambioMiner")

# Definición de variables
fee=0.00001                # Ejemplo de fee

# Cálculo del cambio
cambio=$(echo "$total - $fee - $cantidad_a_enviar" | bc)

# Mostrar el resultado
echo "El cambio que debes dar es: $cambio"


echo "Creando la transacción"
raw_tx=$(bitcoin-cli -rpcwallet="$MINERWALLET" createrawtransaction "$json_inputs" \
    "{\"${empleador_Address}\": $cantidad_a_enviar, \"${minerCambio_Address}\": $cambio}")


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

balance_empleador=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET getbalance)
balance_empleado=$(bitcoin-cli -rpcwallet=$EMPLEADOWALLET getbalance)

echo "Balance - Miner wallet: $balance_miner"
echo "Balance - Empleador wallet: $balance_empleador"
echo "Balance - Empleado wallet: $balance_empleado"


##### SEGUNDA PARTE: Enviar 40 BTC del empleador al empleado




balance=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET getbalance)
echo "Balance - Empleador wallet: $balance"

# Obtener todos los UTXOs de la billetera
utxos=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET listunspent)

echo $utxos
cantidad_utxos=$(echo "$utxos" | jq '. | length')
echo $cantidad_utxos



# Inicializar variables
total=0
inputs=()
cantidad_a_enviar=40


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
    
    
    echo "inputs: ${inputs[@]}"  # Mostrar el contenido del array
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
empleado_Address=$(bitcoin-cli -rpcwallet=$EMPLEADOWALLET getnewaddress "Recibido empleador")
empleadorCambio_Address=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET getnewaddress "CambioMiner")

# Definición de variables
fee=0.00001                # Ejemplo de fee

# Cálculo del cambio
cambio=$(echo "$total - $fee - $cantidad_a_enviar" | bc)

# Mostrar el resultado
echo "El cambio que debes dar es: $cambio"




echo "Creando la transacción"



raw_tx=$(bitcoin-cli -named -rpcwallet="$EMPLEADORWALLET" createrawtransaction \
     "$json_inputs" \
     "{\"${empleado_Address}\": $cantidad_a_enviar, \"${empleador_Address}\": $cambio}" \
     500)

# Firmar la transacción
bitcoin-cli -rpcwallet=$EMPLEADORWALLET walletpassphrase "Contraseña.2" 120
signed_tx=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET signrawtransactionwithwallet "$raw_tx" | jq -r .hex)

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")
echo "TxID de la transacción enviada: $txidEnviada"

block_count=$(bitcoin-cli getblockcount)
echo "Cantidad de bloques generados: $block_count"


#Se obtiene El error -26: non-final, ya que se está tratando de enviar  una transacción cruda no finalizada y, por lo tanto, no puede ser procesada por la red. 
#Esto ocurre, porque tenemos un locktime de 500 bloques. Se minarán 600 bloques, y se reintentará enviar la tx.

#Minando un bloque para confirmar transacciones.
bitcoin-cli generatetoaddress 600 "$minerAddress"


block_count=$(bitcoin-cli getblockcount)
echo "Cantidad de bloques generados: $block_count"


# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")
echo "TxID de la transacción enviada: $txidEnviada"

#Ahora la Tx si pudo ser enviada, ya que se minaron 600 bloques y el locktime de la transacción es de 500 bloques.


#Minando un bloque para confirmar transacciones.
bitcoin-cli generatetoaddress 1 "$minerAddress"










#Balance para Miner
balance_miner=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)

balance_empleador=$(bitcoin-cli -rpcwallet=$EMPLEADORWALLET getbalance)
balance_empleado=$(bitcoin-cli -rpcwallet=$EMPLEADOWALLET getbalance)

echo "Balance - Miner wallet: $balance_miner"
echo "Balance - Empleador wallet: $balance_empleador"
echo "Balance - Empleado wallet: $balance_empleado"