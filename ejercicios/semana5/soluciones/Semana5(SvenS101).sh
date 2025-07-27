#!/usr/bin/env bash

#Script ejercicio de la semana 5 del curso Master Bitcoin From Command Line
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

#Crear las wallets Miner y Alice

echo "¿Crear dos billeteras... Miner y Alice?"
confirm "¿Quieres continuar?"

bitcoin-cli -regtest createwallet "Miner" || echo "Miner ya existe"

bitcoin-cli -regtest createwallet "Alice" || echo "Alice ya existe"

###################################################################################

#Obtener direccion de minado y generar bloques

echo "¿Quiere crear una dirección para minado y generar 101 bloques?"
confirm "¿Quiere continuar?"

DIR_MINER=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress bech32)

echo "Dirección de Miner: $DIR_MINER"

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 101 "$DIR_MINER" > /dev/null

echo "¡Se han minado 101 bloques!"

BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)

sleep 1
echo "El balance de Miner es: $BALANCE BTC"
sleep 1

###################################################################################

#Enviar fondos a Alice

echo "¿Quiere enviar 40 BTC a Alice?"
confirm "¿Quiere continuar?"

DIR_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress bech32)

echo "Dirección de Alice: $DIR_ALICE"

bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$DIR_ALICE" 40.0

echo "Enviando 40 BTC a Alice para fondear su billetera. Generando 1 bloque..."

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

BALANCE_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice getbalance)

sleep 1
echo "El balance de Alice es: $BALANCE_ALICE BTC"
sleep 1

###################################################################################

# Crear transacción con TimeLock relativo

echo "¿Quiere enviar 10 BTC a Miner con un TimeLock relativo de 10 bloques?"
confirm "¿Quieres continuar?"

echo "Dirección de Miner: $DIR_MINER"

DIR_CAMBIO_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "Cambio" bech32)

echo "Dirección de cambio de Alice: $DIR_CAMBIO_ALICE"

UTXO_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice listunspent | jq -c '.[0]')

TXID_ALICE=$(echo "$UTXO_ALICE" | jq -r '.txid')

VOUT_ALICE=$(echo "$UTXO_ALICE" | jq -r '.vout')

VALOR_TOTAL=$(echo "$UTXO_ALICE" | jq -r '.amount')

###################################################################################

# Calcular el valor a enviar

echo "¿Quiere calcular el valor a enviar en la transacción?"
confirm "¿Quiere continuar?"    

FEE=0.001
ENVIO=10.0

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
  --arg txid "$TXID_ALICE" \
  --argjson vout "$VOUT_ALICE" \
  '[{
    "txid": $txid,
    "vout": $vout,
    "sequence": 10
  }]'
)

OUTPUTS=$(jq -c -n \
  --arg dir_miner "$DIR_MINER" \
  --argjson envio "$ENVIO" \
  --arg dir_cambio "$DIR_CAMBIO_ALICE" \
  --argjson cambio "$TOTAL_CAMBIO" \
  '{
      ($dir_miner): $envio,
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

RAW_TX=$(bitcoin-cli -regtest createrawtransaction "$INPUTS" "$OUTPUTS")

echo "Transacción creada con TimeLock relativo de 10 bloques:"

echo "$RAW_TX"

###################################################################################

# Firmar la transacción

FIRMA_TX=$(bitcoin-cli -regtest -rpcwallet=Alice signrawtransactionwithwallet "$RAW_TX" | jq -r '.hex')

###################################################################################

# Intento de envio de la transacción

echo "¿Quiere enviar la transacción con TimeLock relativo de 10 bloques?"
confirm "¿Quiere continuar?"

echo "Enviando la transaccion con TimeLock relativo antes de 10 bloques..."
sleep 1
if ! bitcoin-cli -regtest sendrawtransaction "$FIRMA_TX"; then
    echo "##¡La transacción no se puede transmitir por que aún no se ha alcanzado el TimeLock relativo de 10 bloques!##"
fi

###################################################################################

# Minar 10 bloques

echo "¿Quiere minar 10 bloques?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 10 "$DIR_MINER" > /dev/null

echo "¡Se han minado 10 bloques!"

###################################################################################

# Reintentar transmisión

echo "¿Quiere reintentar la transmisión despues de que se han minado los bloques necesarios?"
confirm "¿Quiere continuar?"

TX_ENVIO=$(bitcoin-cli -regtest sendrawtransaction "$FIRMA_TX")

echo "Transacción enviada: $TX_ENVIO"

echo "Generando 1 bloque para confirmar la transacción..."

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

###################################################################################

# Imprimir balances

echo "¿Quiere conocer los balances de las billeteras?"
confirm "¿Quiere continuar?"

echo "-Balances-"
sleep 1
echo "Balance de Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
sleep 1
echo "Balance de Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"
sleep 1

###################################################################################

#Para reiniciar el nodo y volver a lanzar el script
#Parar bitcoind: bitcoin-cli -regtest stop
#Borrar la carpeta regtest: rm -rf /data/regtest/regtest/*
#Iniciar bitcoid: bitcoind -regtest -daemon
#Comprobar la cadena: bitcoin-cli getblockchaininfo







