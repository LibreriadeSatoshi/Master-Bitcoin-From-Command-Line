#!/usr/bin/env bash

#Script ejercicio de la semana 3 del curso Master Bitcoin From Command Line
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

#Crear las wallets Miner, Alice y Bob

echo "¿Crear tres billeteras... Miner, Alice y Bob?"
confirm "¿Quieres continuar?"

bitcoin-cli -regtest createwallet "Miner" || echo "Miner ya existe"

bitcoin-cli -regtest createwallet "Alice" || echo "Alice ya existe"

bitcoin-cli -regtest createwallet "Bob" || echo "Bob ya existe"

###################################################################################

#Obtener direccion de minado y generar bloques

echo "¿Quiere crear una dirección para minado y generar 103 bloques?"
confirm "¿Quiere continuar?"

DIR_MINER=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress bech32)

echo "Dirección de Miner: $DIR_MINER"

bitcoin-cli -regtest generatetoaddress 103 "$DIR_MINER" > /dev/null

echo "¡Generados 103 bloques!"

BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)

sleep 1

echo "El balance de Miner es: $BALANCE BTC"


###################################################################################

#Enviar fondos a Alice y a Bob

echo "¿Quiere enviar 20 BTC para fondear a Alice y a Bob?"
confirm "¿Quiere continuar?"

DIR_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress bech32)

echo "Dirección de Alice: $DIR_ALICE"

DIR_BOB=$(bitcoin-cli -regtest -rpcwallet=Bob getnewaddress bech32)

echo "Dirección de Bob: $DIR_BOB"

bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$DIR_ALICE" 20.0

bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$DIR_BOB" 20.0

bitcoin-cli -regtest generatetoaddress 2 "$DIR_MINER" > /dev/null

echo "Fondos enviados a Alice y Bob. Generando 2 bloques adicionales..."

BALANCE_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice getbalance)

BALANCE_BOB=$(bitcoin-cli -regtest -rpcwallet=Bob getbalance)

sleep 1

echo "El balance de Alice es: $BALANCE_ALICE BTC"

echo "El balance de Bob es: $BALANCE_BOB BTC"

###################################################################################

# Obtener los descriptores HD de Alice y Bob

echo "¿Quiere obtener los descriptores HD de Alice y Bob?"
confirm "¿Quieres continuar?"

DESC_ALICE_RAW=$(bitcoin-cli -regtest -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc | test("/0/\\*")) | .desc' | head -n1)
  
DESC_BOB_RAW=$(bitcoin-cli -regtest -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc | test("/0/\\*")) | .desc' | head -n1)

DESC_ALICE=$(echo "$DESC_ALICE_RAW" | sed -E 's/^pkh\(([^)]+)\).*/\1/' | sed 's/#.*//')

DESC_BOB=$(echo "$DESC_BOB_RAW" | sed -E 's/^pkh\(([^)]+)\).*/\1/' | sed 's/#.*//')

sleep 1  
echo "Descriptor HD de Alice: $DESC_ALICE"
sleep 1
echo "Descriptor HD de Bob: $DESC_BOB"
sleep 1

###################################################################################

# Crear wallet Multisig con claves extendidas

echo "¿Quiere crear la wallet Multisig 2 de 2 utilizando xpubs de Alice y Bob?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest createwallet "Multisig" false false "" true

DESC_MULTISIG="wsh(multi(2,$DESC_ALICE,$DESC_BOB))"

DESC_CHECKSUM=$(bitcoin-cli -regtest getdescriptorinfo "$DESC_MULTISIG" | jq -r '.descriptor')

DESC_JSON=$(jq -n \
  --arg desc "$DESC_CHECKSUM" \
  --arg label "Multisig 2 de 2 completa" \
  '[{
    "desc": $desc,
    "timestamp": "now",
    "label": $label,
    "active": true,
    "internal": false,
    "range": [0,1000]
  }]')

bitcoin-cli -regtest -rpcwallet=Multisig importdescriptors "$DESC_JSON" > /dev/null

echo "Wallet Multisig creada con éxito e importado el descriptor completo."

###################################################################################

# Derivar dirección multisig

echo "¿Quiere derivar una dirección desde el descriptor Multisig?"
confirm "¿Quiere continuar?"

DIR_MULTISIG=$(bitcoin-cli -regtest -rpcwallet=Multisig getnewaddress "Multisig 2-de-2" bech32)

echo "Dirección multisig derivada: $DIR_MULTISIG"

###################################################################################

#Crear PSBT

echo "¿Quiere crear una PSBT para enviar 10 BTC de Alice y 10 BTC de Bob a multisig?"
confirm "¿Quiere continuar?"

UTXO_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice listunspent | jq -c '.[0]')

UTXO_BOB=$(bitcoin-cli -regtest -rpcwallet=Bob listunspent | jq -c '.[0]')


TXID_ALICE=$(echo "$UTXO_ALICE" | jq -r '.txid')

VOUT_ALICE=$(echo "$UTXO_ALICE" | jq -r '.vout')

VALOR_ALICE=$(echo "$UTXO_ALICE" | jq -r '.amount')


TXID_BOB=$(echo "$UTXO_BOB" | jq -r '.txid')

VOUT_BOB=$(echo "$UTXO_BOB" | jq -r '.vout')

VALOR_BOB=$(echo "$UTXO_BOB" | jq -r '.amount')


DIR_ALICE_CHANGE=$(bitcoin-cli -regtest -rpcwallet=Alice getrawchangeaddress bech32)

DIR_BOB_CHANGE=$(bitcoin-cli -regtest -rpcwallet=Bob getrawchangeaddress bech32)

###################################################################################

#Calcular totales

echo "¿Quiere calcular los totales de Alice y Bob?"
confirm "¿Quiere continuar?"

FEE=0.001
ENVIO=20.0

TOTAL_ENTRADAS=$(jq -n \
  --argjson val_alice "$VALOR_ALICE" \
  --argjson val_bob "$VALOR_BOB" \
  '($val_alice + $val_bob)')

TOTAL_CAMBIO=$(jq -n \
  --argjson total_entradas "$TOTAL_ENTRADAS" \
  --argjson envio "$ENVIO" \
  --argjson fee "$FEE" \
  '($total_entradas - $envio - $fee)')

CAMBIO_X_USUARIO=$(jq -n \
  --argjson total_cambio "$TOTAL_CAMBIO" \
  --argjson num_usuarios 2 \
  '($total_cambio / $num_usuarios)')


echo "Valor total de entradas: $TOTAL_ENTRADAS BTC"
sleep 1
echo "Valor a enviar a Multisig: $ENVIO BTC"
sleep 1
echo "Comisión: $FEE BTC"
sleep 1
echo "Total cambio: $TOTAL_CAMBIO BTC"
sleep 1
echo "Cambio por usuario: $CAMBIO_X_USUARIO BTC"
sleep 1 

###################################################################################

#Construir inputs y outputs

echo "¿Quiere construir los inputs y outputs para la PSBT?"
confirm "¿Quiere continuar?"

INPUTS=$(jq -n \
  --arg txid1 "$TXID_ALICE" \
  --argjson vout1 "$VOUT_ALICE" \
  --arg txid2 "$TXID_BOB" \
  --argjson vout2 "$VOUT_BOB" \
  '[
    {
      "txid": $txid1,
      "vout": $vout1,
      "sequence": 4294967293
    },
    {
      "txid": $txid2,
      "vout": $vout2,
      "sequence": 4294967293
    }
  ]')

OUTPUTS=$(jq -n \
  --arg dir_multi "$DIR_MULTISIG" \
  --argjson btc "$ENVIO" \
  --arg dir_alice "$DIR_ALICE_CHANGE" \
  --argjson cambio1 "$CAMBIO_X_USUARIO" \
  --arg dir_bob "$DIR_BOB_CHANGE" \
  --argjson cambio2 "$CAMBIO_X_USUARIO" \
'{
    ($dir_multi): $btc,
    ($dir_alice): $cambio1,
    ($dir_bob): $cambio2
  }')

  echo "INPUTS generados:"
  echo "$INPUTS" | jq

  echo "Outputs construidos:"
  echo "$OUTPUTS" | jq

  PSBT=$(bitcoin-cli -regtest createpsbt "$INPUTS" "$OUTPUTS" 0)

###################################################################################

#Firmar PSBT

echo "¿Quiere firmar la PSBT?"
confirm "¿Quiere continuar?"

FIRMA_PSBT_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt "$PSBT" | jq -r '.psbt')

FIRMA_PSBT_BOB=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt "$FIRMA_PSBT_ALICE" | jq -r '.psbt')

echo "PSBT firmada por Alice y Bob."

###################################################################################

#Finalizar PSBT y enviar transacción

echo "¿Quiere finalizar la PSBT y enviar la transacción?"
confirm "¿Quiere continuar?"

TX_FINAL=$(bitcoin-cli -regtest finalizepsbt "$FIRMA_PSBT_BOB" | jq -r '.hex')

TXID=$(bitcoin-cli -regtest sendrawtransaction "$TX_FINAL" )

echo "Transacción enviada: $TXID"

###################################################################################

#Confirmar 1 bloque 

echo "¿Quiere confirmar la transacción minando 1 bloque?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

###################################################################################

#Mostrar balances finales

echo "¿Quiere mostrar los balances finales de las billeteras?"
confirm "¿Quiere continuar?"

echo "Balance final de Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
sleep 1
echo "Balance final de Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"
sleep 1
echo "Balance final de Bob: $(bitcoin-cli -regtest -rpcwallet=Bob getbalance) BTC"
sleep 1
echo "Balance final de Multisig: $(bitcoin-cli -regtest -rpcwallet=Multisig getbalance) BTC"
sleep 1

###################################################################################

#Liquidar Multisig: Enviar 3 BTC a Alice desde la wallet Multisig

echo "¿Quiere crear una PSBT para gastar fondos desde Multisig enviando 3 BTC a Alice?"
confirm "¿Quiere continuar?"

#Obtener UTXO de Multisig

UTXO_MULTISIG=$(bitcoin-cli -regtest -rpcwallet=Multisig listunspent | jq -c '.[0]')

TXID_MULTISIG=$(echo "$UTXO_MULTISIG" | jq -r '.txid')

VOUT_MULTISIG=$(echo "$UTXO_MULTISIG" | jq -r '.vout')

###################################################################################

#Obtener dirección de cambio de Multisig

echo "¿Quiere obtener la dirección de cambio de Multisig?"
confirm "¿Quiere continuar?"

DIR_MULTISIG_CHANGE=$(bitcoin-cli -regtest -rpcwallet=Multisig getrawchangeaddress bech32)
echo "Dirección de cambio de Multisig: $DIR_MULTISIG_CHANGE"

###################################################################################

#Calcular totales

echo "¿Quiere calcular los totales de la transacción?"
confirm "¿Quiere continuar?"

FEE=0.001
ENVIO=3.0

VALOR_TOTAL=$(echo "$UTXO_MULTISIG" | jq -r '.amount')

TOTAL_CAMBIO=$(jq -n \
  --argjson total "$VALOR_TOTAL" \
  --argjson envio "$ENVIO" \
  --argjson fee "$FEE" \
  '($total - $envio - $fee)')  

echo "Valor total UTXO: $VALOR_TOTAL BTC"
sleep 1
echo "Valor a enviar a Alice: $ENVIO BTC"
sleep 1
echo "Comisión: $FEE BTC"
sleep 1
echo "Total cambio: $TOTAL_CAMBIO BTC"
sleep 1

###################################################################################

#Construir inputs y outputs para la nueva PSBT

echo "¿Quiere construir los inputs y outputs para la nueva PSBT?"
confirm "¿Quiere continuar?"

INPUTS_MULTISIG=$(jq -c -n \
  --arg txid "$TXID_MULTISIG" \
  --argjson vout "$VOUT_MULTISIG" \
  '[
    {
      "txid": $txid,
      "vout": $vout,
      "sequence": 4294967293
    }
  ]'
)

OUTPUTS_MULTISIG=$(jq -c -n \
  --arg dir_alice "$DIR_ALICE" \
  --argjson envio "$ENVIO" \
  --arg dir_cambio "$DIR_MULTISIG_CHANGE" \
  --argjson val_cambio "$TOTAL_CAMBIO" \
  '{
    ($dir_alice): $envio,
    ($dir_cambio): $val_cambio
  }'
)

echo "INPUTS Multisig generados:"
echo "$INPUTS_MULTISIG" | jq

echo "Outputs Multisig construidos:"
echo "$OUTPUTS_MULTISIG" | jq

###################################################################################

#Crear PSBT para enviar 3 BTC a Alice

echo "¿Quiere crear una PSBT para enviar 3 BTC a Alice?"
confirm "¿Quiere continuar?"

PSBT_MULTISIG=$(bitcoin-cli -regtest createpsbt $INPUTS_MULTISIG $OUTPUTS_MULTISIG 0)

###################################################################################

#Firmar PSBT por Alice y Bob

echo "¿Quiere firmar la PSBT por Alice, Bob y la wallet Multisig?"
confirm "¿Quiere continuar?"

FIRMA_PSBT_MULTISIG_ALICE=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt "$PSBT_MULTISIG" | jq -r '.psbt')

FIRMA_PSBT_MULTISIG_BOB=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt "$FIRMA_PSBT_MULTISIG_ALICE" | jq -r '.psbt')

FIRMA_PSBT_MULTISIG_MULTISIG=$(bitcoin-cli -regtest -rpcwallet=Multisig walletprocesspsbt "$FIRMA_PSBT_MULTISIG_BOB" | jq -r '.psbt')

echo "PSBT Multisig firmada por Alice y Bob."

###################################################################################

#Finalizar PSBT y enviar transacción

echo "¿Quiere finalizar la PSBT y enviar la transacción Multisig?"
confirm "¿Quiere continuar?" 

TX_FINAL_MULTISIG=$(bitcoin-cli -regtest finalizepsbt "$FIRMA_PSBT_MULTISIG_MULTISIG" | jq -r '.hex')

TX_FINAL_SEND_MULTISIG=$(bitcoin-cli -regtest sendrawtransaction "$TX_FINAL_MULTISIG")

echo "Transacción Multisig enviada: $TX_FINAL_SEND_MULTISIG"

###################################################################################

#Confirmar 1 bloque para la transacción Multisig

echo "¿Quiere confirmar la transacción Multisig minando 1 bloque?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER" > /dev/null

###################################################################################

#Mostrar balances finales después de liquidar Multisig

echo "¿Quiere mostrar los balances finales después de liquidar Multisig?"
confirm "¿Quiere continuar?"

echo "Balances finales tras liquidar Multisig:"
sleep 1
echo "Balance final de Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
sleep 1
echo "Balance final de Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"
sleep 1
echo "Balance final de Bob: $(bitcoin-cli -regtest -rpcwallet=Bob getbalance) BTC"
sleep 1
echo "Balance final de Multisig: $(bitcoin-cli -regtest -rpcwallet=Multisig getbalance) BTC"
sleep 1

###################################################################################

#Para reiniciar el nodo y volver a lanzar el script
#Parar bitcoind: bitcoin-cli -regtest stop
#Borrar la carpeta regtest: rm -rf /data/regtest/regtest/*
#Iniciar bitcoid: bitcoind -regtest -daemon
#Comprobar la cadena: bitcoin-cli getblockchaininfo







