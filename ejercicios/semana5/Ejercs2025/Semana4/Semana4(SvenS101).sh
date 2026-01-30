#!/usr/bin/env bash

#Script ejercicio de la semana 4 del curso Master Bitcoin From Command Line
###################################################################################

#Salir si un comando falla

set -e

###################################################################################

#Funcion para pedir confirmación al usuario

confirm() {
	while true; do
		read -p "$1 (s/n): " yn
		case $yn in
			[Ss]* ) return 0;; #Para aceptar (s o S)
			[Nn]* ) echo "Saliendo..."; exit 1;; # Salir (n o N)
			* ) echo "Por favor responde con s o n";;
		esac
	done
}

###################################################################################

#Verificar si bitcoind ya está corriendo

if ! bitcoin-cli -regtest getblockchaininfo > /dev/null 2>&1; then
    echo "bitcoind no está corriendo. Iniciando..."
    bitcoind -regtest -daemon
    echo "Esperando a que bitcoind esté disponible..."
    while ! bitcoin-cli -regtest getblockchaininfo > /dev/null 2>&1; do
        sleep 1
    done
else
    echo "bitcoind ya está corriendo"
fi

###################################################################################

#Crear las wallets Miner, Empleado y Empleador

echo "¿Crear tres billeteras... Miner, Empleado y Empleador?"
confirm "¿Quieres continuar?"

bitcoin-cli -regtest createwallet "Miner" || echo "Miner ya existe"

bitcoin-cli -regtest createwallet "Empleado" || echo "Empleado ya existe"

bitcoin-cli -regtest createwallet "Empleador" || echo "Empleador ya existe"

###################################################################################

#Obtener direccion de minado y generar bloques

echo "¿Quiere crear una dirección para minado y generar 103 bloques?"
confirm "¿Quiere continuar?"

DIR_MINER=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress bech32)

echo "Dirección de Miner: $DIR_MINER"

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 103 "$DIR_MINER" > /dev/null

echo "¡Se han minado 103 bloques!"

BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)

sleep 1
echo "El balance de Miner es: $BALANCE BTC"
sleep 1

###################################################################################

#Enviar fondos a Empleado

echo "¿Quiere enviar 50 BTC en concepto de ganancias al Empleador?"
confirm "¿Quiere continuar?"

DIR_EMPLEADOR=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Ganancias" bech32)

echo "Dirección del Empleador: $DIR_EMPLEADOR"

bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$DIR_EMPLEADOR" 50.0

echo "Enviando 50 BTC de ganancias diarias al Empleador. Generando 1 bloque..."

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

BALANCE_EMPLEADOR=$(bitcoin-cli -regtest -rpcwallet=Empleador getbalance)

sleep 1
echo "El balance del Empleador es: $BALANCE_EMPLEADOR BTC"
sleep 1

###################################################################################

# Crear transacción con TimeLock

echo "¿Quiere enviar 40 BTC en concepto de salario al Empleado con un TimeLock fijado en 500 bloques?"
confirm "¿Quieres continuar?"

DIR_EMPLEADO=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress "Salario" bech32)

echo "Dirección del Empleado: $DIR_EMPLEADO"

DIR_CAMBIO_EMPLEADOR=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Cambio" bech32)

echo "Dirección de cambio del Empleador: $DIR_CAMBIO_EMPLEADOR"

UTXO_EMPLEADOR=$(bitcoin-cli -regtest -rpcwallet=Empleador listunspent | jq -c '.[0]')

TXID_EMPLEADOR=$(echo "$UTXO_EMPLEADOR" | jq -r '.txid')

VOUT_EMPLEADOR=$(echo "$UTXO_EMPLEADOR" | jq -r '.vout')

VALOR_TOTAL=$(echo "$UTXO_EMPLEADOR" | jq -r '.amount')

###################################################################################

# Calcular el valor a enviar

echo "¿Quiere calcular el valor a enviar en la transacción?"
confirm "¿Quiere continuar?"    

FEE=0.001
ENVIO=40.0

TOTAL_CAMBIO=$(jq -n \
  --argjson total "$VALOR_TOTAL" \
  --argjson envio "$ENVIO" \
  --argjson fee "$FEE" \
  '($total - $envio - $fee)')

echo "Valor total UTXO: $VALOR_TOTAL BTC"
sleep 1
echo "Valor a enviar: $ENVIO BTC"
sleep 1
echo "Comisión: $FEE BTC"
sleep 1
echo "Total cambio: $TOTAL_CAMBIO BTC"
sleep 1

###################################################################################

# Construir Inputs y Outputs

echo "¿Quiere construir los inputs y outputs para la transacción?"
confirm "¿Quiere continuar?"

INPUTS=$(jq -c -n \
  --arg txid "$TXID_EMPLEADOR" \
  --argjson vout "$VOUT_EMPLEADOR" \
  '[{
    "txid": $txid,
    "vout": $vout,
    "sequence": 4294967293
  }]'
)

OUTPUTS=$(jq -c -n \
  --arg dir_empleado "$DIR_EMPLEADO" \
  --argjson envio "$ENVIO" \
  --arg dir_cambio "$DIR_CAMBIO_EMPLEADOR" \
  --argjson cambio "$TOTAL_CAMBIO" \
  '{
      ($dir_empleado): $envio,
      ($dir_cambio): $cambio
   }'
)

echo "INPUTS generados:"
echo "$INPUTS" | jq 

echo "Outputs construidos:"
echo "$OUTPUTS" | jq

###################################################################################

# Crear transacción

echo "¿Quiere crear la transacción con los inputs y outputs?"
confirm "¿Quiere continuar?"

RAW_TX=$(bitcoin-cli -regtest createrawtransaction "$INPUTS" "$OUTPUTS" 500)

echo "Transacción creada con TimeLock de 500 bloques:"

echo "$RAW_TX"

###################################################################################

# Firmar la transacción

FIRMA_TX=$(bitcoin-cli -regtest -rpcwallet=Empleador signrawtransactionwithwallet "$RAW_TX" | jq -r '.hex')

###################################################################################

# Intento de envio de la transacción

echo "¿Quiere enviar la transacción con TimeLock antes de 500 bloques?"
confirm "¿Quiere continuar?"

echo "Enviando la transaccion con TimeLock antes de 500 bloques..."
sleep 1
if ! bitcoin-cli -regtest sendrawtransaction "$FIRMA_TX"; then
    echo "######¡La transacción no se puede transmitir por que aún no se ha alcanzado el TimeLock de 500 bloques!######"
fi

###################################################################################

# Minar hasta el bloque 500

echo "¿Quiere minar 500 bloques?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 500 "$DIR_MINER" > /dev/null

echo "¡Se han minado 500 bloques!"

###################################################################################

# Reintentar transmisión

echo "¿Quiere reintentar la transmisión despues de que se han minado los bloques necesarios?"
confirm "¿Quiere continuar?"

TX_SALARIO=$(bitcoin-cli -regtest sendrawtransaction "$FIRMA_TX")

echo "Transacción enviada: $TX_SALARIO"

###################################################################################

# Imprimir balances

echo "¿Quiere conocer los balances de las billeteras?"
confirm "¿Quiere continuar?"

echo "-Balances-"
sleep 1
echo "Balance de Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
sleep 1
echo "Balance del Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
sleep 1
echo "Balance del Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"
sleep 1

###################################################################################

# Crear transacción de gasto con OP_RETURN

echo "¿Quiere crear la transacción de gasto con mensaje en el OP_RETURN?"
confirm "¿Quiere continuar?"

DIR_OP_RETURN=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress bech32)

echo "Dirección para OP_RETURN: $DIR_OP_RETURN"

echo "Generando 1 bloque para confirmar la transacción de salario..."

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

UTXO_EMPLEADO=$(bitcoin-cli -regtest -rpcwallet=Empleado listunspent | jq -c '.[0]')

TXID_EMPLEADO=$(echo "$UTXO_EMPLEADO" | jq -r '.txid')

VOUT_EMPLEADO=$(echo "$UTXO_EMPLEADO" | jq -r '.vout')

VALOR_TOTAL=$(echo "$UTXO_EMPLEADO" | jq -r '.amount')

###################################################################################

# Calcular el valor a enviar

echo "¿Quiere calcular el valor a enviar en la transacción?"
confirm "¿Quiere continuar?"    

FEE=0.001

ENVIO=$(awk "BEGIN {printf \"%.8f\", $VALOR_TOTAL - $FEE}")

TOTAL_CAMBIO=0

echo "Valor total UTXO: $VALOR_TOTAL BTC"
sleep 1
echo "Valor a enviar: $ENVIO BTC"
sleep 1
echo "Comisión: $FEE BTC"
sleep 1
echo "Total cambio: $TOTAL_CAMBIO BTC"
sleep 1

###################################################################################

# Crear script OP_RETURN

echo "¿Quiere crear un script OP_RETURN con un mensaje?"
confirm "¿Quiere continuar?"

MENSAJE="¡He recibido mi salario, ahora soy ricoo!"

MENSAJE_HEX=""
for (( i=0; i<${#MENSAJE}; i++ )); do
  c="${MENSAJE:i:1}"
  hex=$(printf '%02x' "'$c")
  MENSAJE_HEX+="$hex"
done

echo "Mensaje: $MENSAJE"
echo "Mensaje en hexadecimal: $MENSAJE_HEX" 

###################################################################################

# Construir inputs y outputs para la transacción

echo "¿Quiere construir los inputs y outputs para la transacción?"
confirm "¿Quiere continuar?"

INPUTS=$(jq -c -n \
  --arg txid "$TXID_EMPLEADO" \
  --argjson vout "$VOUT_EMPLEADO" \
  '[{
    "txid": $txid,
    "vout": $vout,
    "sequence": 4294967293
  }]'
)

OUTPUTS=$(jq -c -n \
  --arg dir_empleado "$DIR_OP_RETURN" \
  --argjson envio "$ENVIO" \
  --arg data "$MENSAJE_HEX" \
  '{
      ($dir_empleado): $envio ,
      "data": $data
   }'
)

echo "INPUTS generados:"
echo "$INPUTS" | jq

echo "Outputs construidos:"
echo "$OUTPUTS" | jq

###################################################################################

# Crear transaccion 

echo "¿Quiere crear la transacción con los inputs y outputs?"
confirm "¿Quiere continuar?"

RAW_GASTO=$(bitcoin-cli -regtest createrawtransaction "$INPUTS" "$OUTPUTS")

echo "Transacción creada: $RAW_GASTO"

###################################################################################

# Firmar y enviar la transacción

echo "¿Quiere firmar y enviar la transacción?"
confirm "¿Quiere continuar?"

FIRMA_GASTO=$(bitcoin-cli -regtest -rpcwallet=Empleado signrawtransactionwithwallet "$RAW_GASTO" | jq -r '.hex')

TXID_GASTO=$(bitcoin-cli -regtest sendrawtransaction "$FIRMA_GASTO")

echo "Minando 1 bloque para confirmar la transacción..."

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

echo "Transacción enviada: $TXID_GASTO"

###################################################################################

# Mostrar balances finales

echo "¿Quiere mostrar los balances finales de las billeteras?"
confirm "¿Quiere continuar?"

echo "-Balances finales-"
sleep 1
echo "Balance final de Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
sleep 1
echo "Balance final del Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
sleep 1
echo "Balance final del Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"
sleep 1

###################################################################################

#Para reiniciar el nodo y volver a lanzar el script
#Parar bitcoind: bitcoin-cli -regtest stop
#Borrar la carpeta regtest: rm -rf /data/regtest/regtest/*
#Iniciar bitcoid: bitcoind -regtest -daemon
#Comprobar la cadena: bitcoin-cli getblockchaininfo







