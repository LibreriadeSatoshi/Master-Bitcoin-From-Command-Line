#!/bin/bash

# 1. Crea tres monederos: Miner, Empleado y Empleador.

bitcoin-cli createwallet Miner
bitcoin-cli createwallet Empleado
bitcoin-cli createwallet Empleador


# 2. Fondea los monederos generando algunos bloques para Miner y enviando algunas monedas al Empleador.

MINER_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress)
bitcoin-cli generatetoaddress 101 $MINER_ADDR

EMPLEADOR_ADDR=$(bitcoin-cli -rpcwallet=Empleador getnewaddress)

bitcoin-cli -rpcwallet=Miner sendtoaddress $EMPLEADOR_ADDR 45
bitcoin-cli generatetoaddress 1 $MINER_ADDR


# 3. Crea una transacción de salario de 40 BTC, donde el Empleador paga al Empleado.
# 4. Agrega un timelock absoluto de 500 bloques para la transacción, es decir, la transacción no puede incluirse en el bloque hasta que se haya minado el bloque 500.

EMPLEADO_ADDR=$(bitcoin-cli -rpcwallet=Empleado getnewaddress)
EMPLEADOR_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Empleador getrawchangeaddress)

UTXO=$(bitcoin-cli -rpcwallet=Empleador listunspent)
TXID=$(echo $UTXO | jq -r '.[0].txid')
VOUT=$(echo $UTXO | jq -r '.[0].vout')

RAW_TX=$(bitcoin-cli -rpcwallet=Empleador createrawtransaction \
  "[{\"txid\":\"$TXID\", \"vout\":$VOUT}]" \
  "[{\"$EMPLEADO_ADDR\":40}, {\"$EMPLEADOR_CHANGE_ADDR\":4.99999}]" \
  500)

SIGNED_TX=$(bitcoin-cli -rpcwallet=Empleador signrawtransactionwithwallet "$RAW_TX" | jq -r .hex)


# 5. Informa en un comentario qué sucede cuando intentas transmitir esta transacción.

ERROR=$(bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$SIGNED_TX" 2>&1)
echo $ERROR
echo "No se puede agregar la transacción al bloque debido al timelock absoluto. Solo a partir del bloque 500 se podría minar".


# 6. Mina hasta el bloque 500 y transmite la transacción.

while [ "$(bitcoin-cli getblockcount)" -lt 500 ]; do
  bitcoin-cli generatetoaddress 1 "$(bitcoin-cli -rpcwallet=Miner getnewaddress)"
done

SENT=$(bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$SIGNED_TX")


# 7. Imprime los saldos finales del Empleado y Empleador.

bitcoin-cli -rpcwallet=Empleador getbalance
bitcoin-cli -rpcwallet=Empleado getbalance


# Minamos un bloque mas para ver el saldo del empleado reflejado

bitcoin-cli generatetoaddress 1 "$(bitcoin-cli -rpcwallet=Miner getnewaddress)"

bitcoin-cli -rpcwallet=Empleador getbalance
bitcoin-cli -rpcwallet=Empleado getbalance


# 8. Crea una transacción de gasto en la que el Empleado gaste los fondos a una nueva dirección de monedero del Empleado.

EMPLEADO_CHANGE_ADDR=$(bitcoin-cli -rpcwallet=Empleado getnewaddress)
UTXO2=$(bitcoin-cli -rpcwallet=Empleado listunspent)
TXID2=$(echo $UTXO2 | jq -r '.[0].txid')
VOUT2=$(echo $UTXO2 | jq -r '.[0].vout')


# 9. Agrega una salida OP_RETURN en la transacción de gasto con los datos de cadena "He recibido mi salario, ahora soy rico".

apt-get install xxd
HEX_DATA=$(echo -n "He recibo mi salario, ahora soy rico" | xxd -p | tr -d '\n')

RAW_TX2=$(bitcoin-cli -rpcwallet=Empleado createrawtransaction \
  "[{\"txid\":\"$TXID2\", \"vout\":$VOUT2}]" \
  "[{\"$EMPLEADO_CHANGE_ADDR\":39.99999}, {\"data\":\"$HEX_DATA\"}]")


# 10. Extrae y transmite la transacción completamente firmada.
SIGNED_TX2=$(bitcoin-cli -rpcwallet=Empleado signrawtransactionwithwallet "$RAW_TX2" | jq -r .hex)

SENT2=$(bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$SIGNED_TX2")


# 11. Imprime los saldos finales del Empleado y Empleador.

bitcoin-cli -rpcwallet=Empleador getbalance
bitcoin-cli -rpcwallet=Empleado getbalance