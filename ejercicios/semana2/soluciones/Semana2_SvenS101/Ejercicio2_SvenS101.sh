#!/usr/bin/env bash


#Script ejercicio de la semana 2 del curso Master Bitcoin From Command Line
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

#Crear las dos wallets

echo "¿Crear dos billeteras... una Miner y otra Trader?"
confirm "¿Quieres continuar?"

bitcoin-cli -regtest createwallet "Miner" || echo "Miner ya existe"
bitcoin-cli -regtest createwallet "Trader" || echo "Trader ya existe"

###################################################################################

#Obtener direcciones de Miner y Trader

echo "¿Quiere crear dos direcciones una en cada billetera?"
confirm "¿Quiere continuar?"

DIR_MINER=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress bech32)
echo "Dirección de Miner: $DIR_MINER"

DIR_TRADER=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress bech32)
echo "Dirección de Trader: $DIR_TRADER"

###################################################################################

#Generar 103 bloques a la dirección del Miner (150 BTC: 3 recompensas de 50 BTC + maduración)

echo "¿Quiere generar 103 bloques para poder fondear Miner?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest generatetoaddress 103 "$DIR_MINER" > /dev/null

echo "¡Generados 103 bloques!"

BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)

sleep 1

echo "El balance de Miner es: $BALANCE"

###################################################################################

#Listar UTXOs del Miner

echo "¿Quiere listar los UTXOs?"
confirm "¿Quiere continuar?"

UTXOS=$(bitcoin-cli -regtest -rpcwallet=Miner listunspent | jq -c '.[:2]')

TXID0=$(echo "$UTXOS" | jq -r '.[0].txid')

VOUT0=$(echo "$UTXOS" | jq -r '.[0].vout')

TXID1=$(echo "$UTXOS" | jq -r '.[1].txid')

VOUT1=$(echo "$UTXOS" | jq -r '.[1].vout')

echo "Primer UTXO: $TXID0:$VOUT0"

echo "Segundo UTXO: $TXID1:$VOUT1"

###################################################################################

#Construir inputs

echo "¿Quiere construir los inputs?"
confirm "¿Quiere continuar?"

INPUTS=$(jq -n \
  --arg txid0 "$TXID0" \
  --argjson vout0 "$VOUT0" \
  --arg txid1 "$TXID1" \
  --argjson vout1 "$VOUT1" \
'[
  {
    "txid": $txid0,
    "vout": $vout0,
    "sequence": 4294967293
  },
  {
    "txid": $txid1,
    "vout": $vout1,
    "sequence": 4294967293
  }
]')

echo "INPUTS generados:"
echo "$INPUTS" | jq

###################################################################################

#Construir outputs (Trader: 70 BTC, Miner cambio: 29.99999 BTC)

echo "¿Quiere construir los outputs?"
confirm "¿Quiere continuar?"

OUTPUTS=$(jq -n \
  --arg trader "$DIR_TRADER" \
  --arg miner "$DIR_MINER" \
'{
  ($trader): 70.0,
  ($miner): 29.99999
}')

echo "Outputs construidos:"
echo "$OUTPUTS" | jq

###################################################################################

#Crear raw transaction

echo "¿Quiere crear la transacción 'parent'?"
confirm "¿Quiere continuar?"

RAW_PARENT_TX=$(bitcoin-cli -regtest createrawtransaction "$INPUTS" "$OUTPUTS")

echo "Transacción 'parent' creada:"
echo "$RAW_PARENT_TX"

###################################################################################

#Firmar

echo "¿Quiere firmar la transacción 'parent'?"
confirm "¿Quiere continuar?"

SIGNED_PARENT_TX=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$RAW_PARENT_TX" | jq -r '.hex')

echo "Transacción 'parent' firmada:"
echo "$SIGNED_PARENT_TX"

###################################################################################

#Transmitir

echo "¿Quiere transmitir la transacción 'parent'?"
confirm "¿Quiere continuar?"

TXID_PARENT=$(bitcoin-cli -regtest sendrawtransaction "$SIGNED_PARENT_TX")

echo "TX parent enviada al mempool: $TXID_PARENT"

sleep 1

###################################################################################

#Obtener detalles de la transacción de la mempool

echo "¿Quiere obtener detalles en la mempool de la transacción 'parent'?"
confirm "¿Quiere continuar?"

echo "Detalles mempool de la transacción 'parent':"
bitcoin-cli -regtest getmempoolentry "$TXID_PARENT"

MEMPOOL_TX=$(bitcoin-cli -regtest getmempoolentry "$TXID_PARENT")

###################################################################################

#Obtener script de bloqueo de las direcciones

echo "¿Quiere obtener el script de bloqueo de las direcciones?"
confirm "¿Quiere continuar?"

MINER_SCRIPT=$(bitcoin-cli -regtest -rpcwallet=Miner getaddressinfo "$DIR_MINER" | jq -r '.scriptPubKey')

TRADER_SCRIPT=$(bitcoin-cli -regtest -rpcwallet=Trader getaddressinfo "$DIR_TRADER" | jq -r '.scriptPubKey')

echo "Script de bloqueo de Miner: $MINER_SCRIPT"

echo "Script de bloqueo de Trader: $TRADER_SCRIPT"

###################################################################################

#Construir JSON de salida

echo "¿Quiere construir el JSON de salida?"
confirm "¿Quiere continuar?"

jq -n \
  --arg txid0 "$TXID0" --argjson vout0 "$VOUT0" \
  --arg txid1 "$TXID1" --argjson vout1 "$VOUT1" \
  --arg m_script "$MINER_SCRIPT" --arg t_script "$TRADER_SCRIPT" \
  --arg m_amt "29.99999" --arg t_amt "70.0" \
  --arg fee "$(echo "$MEMPOOL_TX" | jq '.fees.base')" \
  --arg weight "$(echo "$MEMPOOL_TX" | jq '.weight')" \
'{
  input: [
    { txid: $txid0, vout: $vout0 },
    { txid: $txid1, vout: $vout1 }
  ],
  output: [
    { script_pubkey: $m_script, amount: $m_amt },
    { script_pubkey: $t_script, amount: $t_amt }
  ],
  Fees: $fee,
  Weight: $weight
}'

###################################################################################

#Crear transacción child que gasta salida de Miner de la transacción parent

echo "¿Quiere crear la transacción child que gasta la salida de Miner de parent?"
confirm "¿Quiere continuar?"

#Obtenemos el índice de la salida de Miner en parent
#Sabemos que salida 1 es el cambio para Miner (29.99999 BTC)
PARENT_CHILD_VOUT=1

###################################################################################

#Nueva dirección para Miner en child

echo "¿Quiere generar una nueva direccion para child de Miner?"
confirm "¿Quiere continuar?"

DIR_MINER_CHILD=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress bech32)
echo "Nueva dirección Miner para la transacción child: $DIR_MINER_CHILD"

###################################################################################

#Construimos inputs (gastando la salida de Miner de parent)

echo "¿Quiere construir los inputs gastando la salida de Miner 'parent'?"
confirm "¿Quiere continuar?"

echo "TXID_PARENT: $TXID_PARENT"

CHILD_INPUT=$(jq -n \
  --arg txid "$TXID_PARENT" \
  --argjson vout "$PARENT_CHILD_VOUT" \
'[{"txid": $txid, "vout": $vout, "sequence": 4294967293}]')

echo "INPUTS generados:"
echo "$CHILD_INPUT" | jq

###################################################################################

#Construimos outputs child: 29.99998 BTC a la nueva dirección Miner (ligero fee para child)

echo "¿Quiere construir los outputs child a la nueva dirección Miner?"
confirm "¿Quiere continuar?"

OUTPUTS_CHILD=$(jq -n \
  --arg addr "$DIR_MINER_CHILD" \
'{ ($addr): 29.99998 }')

echo "OUTPUTS generados:"
echo "$OUTPUTS_CHILD" | jq

###################################################################################

#Creamos raw transaction child

echo "¿Quiere crear la raw transaction child?"
confirm "¿Quiere continuar?"

RAW_CHILD_TX=$(bitcoin-cli -regtest createrawtransaction "$CHILD_INPUT" "$OUTPUTS_CHILD")

echo "Transaccion child creada"
echo "$RAW_CHILD_TX"

###################################################################################

#Firmamos la transacción child

echo "¿Quiere firmar la raw transaction child?"
confirm "¿Quiere continuar?"

SIGNED_CHILD_TX=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$RAW_CHILD_TX" | jq -r '.hex')

echo "Transaccion child firmada"
echo "$SIGNED_CHILD_TX"

###################################################################################

#Transmitimos la transacción child

echo "¿Quiere transmitir la raw transaction child?"
confirm "¿Quiere continuar?"

TXID_CHILD=$(bitcoin-cli -regtest sendrawtransaction "$SIGNED_CHILD_TX")
echo "Transacción child enviada al mempool: $TXID_CHILD"

###################################################################################

#Consultar getmempoolentry para child

echo "¿Quiere consultar la mempool para ver la child transaction?"
confirm "¿Quiere continuar?"

echo "Detalles mempool de la transacción child:"
bitcoin-cli -regtest getmempoolentry "$TXID_CHILD"

###################################################################################

#Aumentar tarifa de la transacción parent manualmente con RBF (10,000 satoshis más fee)

echo "¿Quiere crear una transacción conflictiva para aumentar tarifa de parent en 10,000 satoshis?"
confirm "¿Quiere continuar?"

# Nueva salida para parent con tarifa aumentada en 0.0001 BTC (10,000 sats)
# Salida a Trader: 70 BTC (igual)
# Salida a Miner: 29.99989 BTC (reducción para aumentar tarifa)

OUTPUTS_PARENT_RPLC=$(jq -n \
  --arg trader "$DIR_TRADER" \
  --arg miner "$DIR_MINER" \
'{
  ($trader): 70.0,
  ($miner): 29.99989
}')

echo "OUTPUTS generados:"
echo "$OUTPUTS_PARENT_RPLC" | jq
###################################################################################

#Crear raw transaction con mismas inputs y outputs modificados

echo "¿Quiere crear la raw transaction con mismos inputs y outputs modificados?"
confirm "¿Quiere continuar?"

RAW_PARENT_TX_RPLC=$(bitcoin-cli -regtest createrawtransaction "$INPUTS" "$OUTPUTS_PARENT_RPLC")

echo "Transacción 'parent' con tarifa mayor creada"
echo "$RAW_PARENT_TX_RPLC"

###################################################################################

#Firmar tx parent con tarifa aumentada

echo "¿Quiere firmar la transaction parent con tarifa aumentada?"
confirm "¿Quiere continuar?"

SIGNED_PARENT_TX_RPLC=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$RAW_PARENT_TX_RPLC" | jq -r '.hex')

echo "Transacción 'parent' con tarifa mayor firmada"
echo $SIGNED_PARENT_TX_RPLC

###################################################################################

#Transmitir tx parent con tarifa aumentada (reemplazo RBF)

echo "¿Quiere transmitir la transaction parent con tarifa aumentada?"
confirm "¿Quiere continuar?"

TXID_PARENT_RPLC=$(bitcoin-cli -regtest sendrawtransaction "$SIGNED_PARENT_TX_RPLC")

echo "Transacción 'parent' reemplazada con tarifa mayor y enviada: $TXID_PARENT_RPLC"

###################################################################################

#Actualizar TXID_PARENT a la tx reemplazada

echo "¿Quiere actualizar el TXID de parent con la TXID de parent con tarifa aumentada?"
confirm "¿Quiere continuar?"

TXID_PARENT="$TXID_PARENT_RPLC"

echo "El nuevo TXID es: $TXID_PARENT"

###################################################################################

#Construir nuevo input child con el nuevo TXID_PARENT

echo "¿Quiere construir nuevo input con el nuevo TXID?"
confirm "¿Quiere continuar?"

CHILD_INPUT=$(jq -n \
  --arg txid "$TXID_PARENT" \
  --argjson vout "$PARENT_CHILD_VOUT" \
  '[{"txid": $txid, "vout": $vout, "sequence": 4294967293}]')

echo "INPUTS generados:"
echo "$CHILD_INPUT" | jq

###################################################################################

#Construir outputs child igual que antes

echo "¿Quiere construir output con la misma tarifa?"
confirm "¿Quiere continuar?"

CHILD_OUTPUT=$(jq -n \
  --arg addr "$DIR_MINER_CHILD" \
  '{ ($addr): 29.99988 }')

echo "OUTPUTS generados:"
echo "$CHILD_OUTPUT" | jq

###################################################################################

#Crear la child con el nuevo input

echo "¿Quiere crear la child transaction con el nuevo input?"
confirm "¿Quiere continuar?"

RAW_CHILD=$(bitcoin-cli -regtest createrawtransaction "$CHILD_INPUT" "$CHILD_OUTPUT")

echo $RAW_CHILD

###################################################################################

#Firmar la child con el nuevo input

echo "¿Quiere firmar la child transaction con el nuevo input?"
confirm "¿Quiere continuar?"

SIGNED_CHILD=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$RAW_CHILD" | jq -r '.hex')

echo $SIGNED_CHILD

###################################################################################

#Transmitir la nueva child

echo "¿Quiere transmitir la child transaction con el nuevo input?"
confirm "¿Quiere continuar?"

TXID_CHILD=$(bitcoin-cli -regtest sendrawtransaction "$SIGNED_CHILD")

echo "Nueva transacción child enviada con parent actualizado: $TXID_CHILD"

###################################################################################

#Consultar getmempoolentry para child tras reemplazo de parent

echo "¿Quiere consultar en la mempool la transaction child tras el reemplazo de parent?"
confirm "¿Quiere continuar?"

echo "Detalles mempool de la transacción child tras el reemplazo de parent:"
bitcoin-cli -regtest getmempoolentry "$TXID_CHILD"

###################################################################################

sleep 1

#Explicación

echo -e "\n--- EXPLICACIÓN ---"
echo "La transacción parent fue sustituida en la mempool por otra versión con una comisión 10.000 sats más alta."
echo "Esto afecta a la transacción child porque depende de una salida creada por parent (la de Miner)."
echo "Al subir la fee de parent, el nodo reevalúa su prioridad y la de child en la mempool."
echo "Por eso al hacer getmempoolentry sobre child puede cambiar el estado, el fee total que ve el nodo o el tiempo que lleva esperando."
echo "Esta técnica se llama CPFP (child-pays-for-parent) y se usa para acelerar la confirmación de ambas cuando una depende de la otra."
