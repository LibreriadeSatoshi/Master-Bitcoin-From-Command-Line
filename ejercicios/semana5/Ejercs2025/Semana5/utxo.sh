#!/bin/bash

# Configurar un timelock relativo
# -------------------------------

clear
echo "-------------------------------"
echo "       Ejercicio semana 5      "
echo "-------------------------------"
echo ""

# 1. Crear dos billeteras: Miner, Alice.
bitcoin-cli createwallet Miner > /dev/null 2>&1
MINER_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress)

bitcoin-cli createwallet Alice > /dev/null 2>&1
ALICE_ADDR=$(bitcoin-cli -rpcwallet=Alice getnewaddress)


# 2. Fondear las billeteras generando algunos bloques para Miner y enviando algunas monedas a Alice.

bitcoin-cli generatetoaddress 101 $MINER_ADDR > /dev/null 2>&1

TXID=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[].txid')
VOUT=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[].vout')

MINER_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Miner getrawchangeaddress)

RAW_TX=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[{\"txid\":\"$TXID\",\"vout\":$VOUT}]" "[{\"$ALICE_ADDR\":15}, {\"$MINER_CHANGE_ADDR\":34.99999}]")

SIGNED_TX=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $RAW_TX | jq -r '.hex')

TXID2=$(bitcoin-cli sendrawtransaction $SIGNED_TX)


# 3. Confirmar la transacción y chequar que Alice tiene un saldo positivo.

bitcoin-cli generatetoaddress 1 $MINER_ADDR > /dev/null 2>&1

ALICE_BALANCE=$(bitcoin-cli -rpcwallet=Alice getbalance)
if (( $(echo "$ALICE_BALANCE > 0" | bc -l) )); then
    echo "El balance de Alice es positivo: $ALICE_BALANCE BTC"
else
    echo "Error: El balance de Alice es 0: $ALICE_BALANCE BTC"
    exit 1
fi

# 4. Crear una transacción en la que Alice pague 10 BTC al Miner, pero con un timelock relativo de 10 bloques.

VOUT2=$(bitcoin-cli -rpcwallet=Alice listunspent | jq -r '.[].vout')
ALICE_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Alice getrawchangeaddress)

RAW_TX2=$(bitcoin-cli -rpcwallet=Alice createrawtransaction "[{\"txid\":\"$TXID2\",\"vout\":$VOUT2,\"sequence\":10}]" "[{\"$ALICE_CHANGE_ADDR\":4.99999}, {\"$MINER_ADDR\":10}]")



# 5. Informar en la salida del terminal qué sucede cuando intentas difundir la segunda transacción.

SIGNED_TX2=$(bitcoin-cli -rpcwallet=Alice signrawtransactionwithwallet $RAW_TX2 | jq -r '.hex')

echo -e "\nEnviando transaccion antes de cumplirse el locktime de 10 bloques..."
TXID3=$(bitcoin-cli sendrawtransaction $SIGNED_TX2) 

echo -e "\nnon-BIP68-final: el nodo rechaza la transaccion porque la transaccion padre (TXID2) tiene menos de 10 confirmaciones. Hay que esperar hasta que TXID2 tenga al menos 10 confirmaciones (10 bloques minados desde que se incluyo en un bloque).\n"



# Gastar desde el timelock relativo
# -------------------------------

# 1. Generar 10 bloques adicionales.

echo "Generar 10 bloques adicionales"
bitcoin-cli generatetoaddress 10 $MINER_ADDR > /dev/null 2>&1


# 2. Difundir la segunda transacción. Confirmarla generando un bloque más.

echo -e "\nSaldo de Alice antes de enviar la transaccion: $(bitcoin-cli -rpcwallet=Alice getbalance)\n"

echo "Enviando transaccion antes de cumplirse el locktime de 10 bloques..."

TXID3=$(bitcoin-cli sendrawtransaction $SIGNED_TX2)
bitcoin-cli generatetoaddress 1 $MINER_ADDR > /dev/null 2>&1


# 3. Informar el saldo de Alice.

echo "Saldo de Alice despues de enviar la transaccion: $(bitcoin-cli -rpcwallet=Alice getbalance)"


# 4. - [OPCIONAL] - Gastar el UTXO que estaba en la transaccion con locktime y devolverselo a Alice.

echo -e "\n[OPCIONAL] - Gastando el UTXO que estaba en la transaccion con locktime y devolviendoselo a Alice."
VOUT3=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r ".[] | select(.txid == \"$TXID3\")" | jq -r '.vout')
ALICE_ADDR2=$(bitcoin-cli -rpcwallet=Alice getnewaddress)


RAW_TX3=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[{\"txid\":\"$TXID3\",\"vout\":$VOUT3}]" "[{\"$ALICE_ADDR2\":9.99999}]")

SIGNED_TX3=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $RAW_TX3 | jq -r '.hex')

TXID4=$(bitcoin-cli sendrawtransaction $SIGNED_TX3)
bitcoin-cli generatetoaddress 1 $MINER_ADDR > /dev/null 2>&1

echo "Saldo de Alice despues de recibir el output de la transaccion con timelock: $(bitcoin-cli -rpcwallet=Alice getbalance)"
