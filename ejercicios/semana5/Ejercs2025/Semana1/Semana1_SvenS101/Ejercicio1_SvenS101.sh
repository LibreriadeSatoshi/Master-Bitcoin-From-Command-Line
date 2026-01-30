#!/usr/bin/env bash


#Script ejercicio de la semana 1 del curso Master Bitcoin From Command Line
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

#Generar dirección recompensa de mineria desde la billetera Miner

echo "¿Generar la direccion 'Recompensa de mineria' desde la billetera Miner?"
confirm "¿Quieres continuar?"

DIR_MINER=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Recompensa de Mineria" bech32)
echo "Dirección de Miner: $DIR_MINER"

###################################################################################

#Extraer bloques

echo "¿Quiere generar bloques para obtener fondos utilizables?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER"
bitcoin-cli -regtest -rpcwallet=Miner getbalance

echo "¿Minar 101 bloques?"
confirm "¿Continuar?"

bitcoin-cli -regtest generatetoaddress 101 "$DIR_MINER"

###################################################################################

#Imprimir el saldo de la billetera

echo "¿Quiere imprimir el saldo de la billetera Miner?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest -rpcwallet=Miner getbalance

sleep 1

echo -e "\n--- EXPLICACIÓN ---"
echo "El saldo de la billetera Miner no muestra inmediatamente las recompensas por bloque."
echo "Cada recompensa necesita 100 confirmaciones antes de considerarse 'madura' y poder gastarse"
echo "por eso no se refleja en el balance hasta después de minar 101 bloques."


###################################################################################

#Crear una dirección en la billetera Trader

echo "¿Generar la direccion 'Recibido' desde la billetera Trader?"
confirm "¿Quiere continuar?"

DIR_TRADER=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Recibido" bech32)
echo "Dirección de Trader: $DIR_TRADER"

###################################################################################

#Enviar 20 btc de Miner a Trader

echo "¿Enviar 20 btc de Miner a Trader?"
confirm "¿Quiere continuar?"

TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$DIR_TRADER" 20)
echo "TXID: $TXID"

###################################################################################

#Obtener la tx no confirmada desde mempool

echo "¿Quiere obtener la tx no confirmada desde la mempool?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest getmempoolentry "$TXID"

###################################################################################

#Confirmar la tx minando un bloque

echo "¿Quiere minar 1 bloque para confirmar la tx?"
confirm "¿Quiere continuar?"

bitcoin-cli -regtest generatetoaddress 1 "$DIR_MINER"

###################################################################################

#Obtener los detalles de la tx

echo "¿Quiere obtener los detalles de la tx?"
confirm "¿Quiere continuar?"

TXINFO=$(bitcoin-cli -regtest -rpcwallet=Miner gettransaction "$TXID")
RAW_HEX=$(echo "$TXINFO" | jq -r '.hex')
RAW=$(bitcoin-cli -regtest decoderawtransaction "$RAW_HEX")

#Mostrar detalles
echo "TXID: $TXID"
echo "Dirección de Trader (destino):"
echo "$RAW" | jq -r '.vout[] | select(.value==20) | .scriptPubKey.address'

echo "Dirección de Miner (cambio):"
echo "$RAW" | jq -r '.vout[] | select(.value!=20.0) | .scriptPubKey.address'

echo "Comisión:"
echo "$TXINFO" | jq '.fee'

echo "Bloque de confirmación:"
echo "$TXINFO" | jq '.blockheight'

###################################################################################

#Obtener el saldo en ambas billeteras

echo "¿Quiere obtener el saldo en ambas billeteras?"
confirm "¿Quiere continuar?"

echo "Saldo Miner:"
bitcoin-cli -regtest -rpcwallet=Miner getbalance

echo "Saldo Trader:"
bitcoin-cli -regtest -rpcwallet=Trader getbalance

###################################################################################

#Para reiniciar el nodo y volver a lanzar el script
#Parar bitcoind: bitcoin-cli -regtest stop
#Borrar la carpeta regtest: rm -rf /data/regtest/regtest/*
#Iniciar bitcoid: bitcoind -regtest -daemon
#Comprobar la cadena: bitcoin-cli getblockchaininfo
