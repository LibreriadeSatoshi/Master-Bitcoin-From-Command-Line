#!/bin/bash
export PATH="$PWD/bitcoin-30.2/bin:$PATH"
rm -rf ~/.bitcoin/regtest/
./bitcoin-30.2/bin/bitcoind -daemon
sleep 3

#### Configurar un contrato Timelock

# 1. Crea tres monederos: `Miner`, `Empleado` y `Empleador`.
alias bitcoin-cli="bitcoin-30.2/bin/bitcoin-cli -regtest -rpcuser=usuario -rpcpassword=contraseña"
bitcoin-cli createwallet Miner &&> /dev/null
bitcoin-cli loadwallet Miner &> /dev/null
bitcoin-cli createwallet Empleado &> /dev/null
bitcoin-cli loadwallet Empleado &> /dev/null
bitcoin-cli createwallet Empleador &> /dev/null
bitcoin-cli loadwallet Empleador &> /dev/null

# 2. Fondea los monederos generando algunos bloques para `Miner` y enviando algunas monedas al `Empleador`.
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
bitcoin-cli generatetoaddress 101 "$miner_address" &> /dev/null
empleador_address=$(bitcoin-cli -rpcwallet=Empleador getnewaddress "Fondeo")
bitcoin-cli -rpcwallet=Miner sendtoaddress "$empleador_address" 49 &> /dev/null
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null

# 3. Crea una transacción de salario de 40 BTC, donde el `Empleador` paga al `Empleado`.
# 4. Agrega un timelock absoluto de 500 bloques para la transacción, es decir, la transacción no puede incluirse en el bloque hasta que se haya minado el bloque 500.
empleador_utxo=$(bitcoin-cli -rpcwallet=Empleador listunspent | jq '.[0]')
empleador_txid=$(echo "$empleador_utxo" | jq -r '.txid')
empleador_vout=$(echo "$empleador_utxo" | jq -r '.vout')
empleador_change_address=$(bitcoin-cli -rpcwallet=Empleador getrawchangeaddress)
empleado_address=$(bitcoin-cli -rpcwallet=Empleado getnewaddress "Fondeo")
tx_hex=$(bitcoin-cli -named createrawtransaction  inputs="[{\"txid\": \"$empleador_txid\", \"vout\": $empleador_vout}]"  outputs="[{\"${empleado_address}\": 40},  {\"${empleador_change_address}\": 8.99999}]"  locktime=500)
tx_signed=$(bitcoin-cli -rpcwallet=Empleador signrawtransactionwithwallet "$tx_hex" | jq -r '.hex')
echo "enviar transacción con timelock absoluto de 500 bloques antes de que se alcance el bloque 500..."
bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$tx_signed"

# 5. Informa en un comentario qué sucede cuando intentas transmitir esta transacción.
echo "Cuando se intenta transmitir esta transacción, el nodo da el error \"non-final\", ya que tiene un timelock absoluto de 500 bloques."

# 6. Mina hasta el bloque 500 y transmite la transacción.
echo "Minando hasta el bloque 500..."
bitcoin-cli generatetoaddress 398 "$miner_address" &> /dev/null
echo "Enviar la transacción después de alcanzar el bloque 500..."
echo "Bloque actual: $(bitcoin-cli getblockcount)"
bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$tx_signed"
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null

# 7. Imprime los saldos finales del `Empleado` y `Empleador`.
echo "Ahora sí, el empleado ha recibido su salario, el timelock ha expirado y la transacción se ha confirmado."
empleado_balance=$(bitcoin-cli -rpcwallet=Empleado getbalance)
empleador_balance=$(bitcoin-cli -rpcwallet=Empleador getbalance)
echo "Saldo del Empleado: $empleado_balance BTC"
echo "Saldo del Empleador: $empleador_balance BTC"

#### Gastar desde el Timelock
# 1. Crea una transacción de gasto en la que el `Empleado` gaste los fondos a una nueva dirección de monedero del `Empleado`.
# 2. Agrega una salida `OP_RETURN` en la transacción de gasto con los datos de cadena `"He recibido mi salario, ahora soy rico"`.
empleado_new_address=$(bitcoin-cli -rpcwallet=Empleado getnewaddress "Destino")
empleado_utxo=$(bitcoin-cli -rpcwallet=Empleado listunspent | jq '.[0]')
empleado_txid=$(echo "$empleado_utxo" | jq -r '.txid')
empleado_vout=$(echo "$empleado_utxo" | jq -r '.vout')
empleado_change_address=$(bitcoin-cli -rpcwallet=Empleado getrawchangeaddress)
data_hex=$(echo -n "He recibido mi salario, ahora soy rico" | xxd -p | tr -d '\n')
tx_hex=$(bitcoin-cli -named createrawtransaction  inputs="[{\"txid\": \"$empleado_txid\", \"vout\": $empleado_vout}]"  outputs="[{\"${empleado_new_address}\": 39.99999}, {\"data\": \"${data_hex}\"}]" )
# 3. Extrae y transmite la transacción completamente firmada.
tx_signed=$(bitcoin-cli -rpcwallet=Empleado signrawtransactionwithwallet "$tx_hex" | jq -r '.hex')
bitcoin-cli -rpcwallet=Empleado sendrawtransaction "$tx_signed"
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null
# 4. Imprime los saldos finales del `Empleado` y `Empleador`.
echo "El empleado ha gastado solo la fee y ha incluido un mensaje en la blockchain con OP_RETURN."
empleado_balance=$(bitcoin-cli -rpcwallet=Empleado getbalance)
empleador_balance=$(bitcoin-cli -rpcwallet=Empleador getbalance)
echo "Saldo del Empleado: $empleado_balance BTC"
echo "Saldo del Empleador: $empleador_balance BTC"

#### Configurar un timelock relativo
# 1. Crear una transacción en la que `Empleador` pague 1 BTC a `Miner`, pero con un timelock relativo de 10 bloques.
empleador_utxo=$(bitcoin-cli -rpcwallet=Empleador listunspent | jq '.[0]')
empleador_txid=$(echo "$empleador_utxo" | jq -r '.txid')
empleador_vout=$(echo "$empleador_utxo" | jq -r '.vout')
empleador_change_address=$(bitcoin-cli -rpcwallet=Empleador getrawchangeaddress)
new_miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Fondeo")
tx_hex=$(bitcoin-cli -named createrawtransaction  inputs="[{\"txid\": \"$empleador_txid\", \"vout\": $empleador_vout, \"sequence\": 10}]"  outputs="[{\"${new_miner_address}\": 1},  {\"${empleador_change_address}\": 7.99998}]")
tx_signed=$(bitcoin-cli -rpcwallet=Empleador signrawtransactionwithwallet "$tx_hex" | jq -r '.hex')

# 2. Informar en la salida del terminal qué sucede cuando intentas difundir la transacción.
bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$tx_signed"
echo "Cuando se intenta transmitir esta transacción, el nodo da error non-BIP68-final porque no han pasado 10 bloques desde la transacción padre."

#### Gastar desde el timelock relativo
echo "minar diez bloques más"
# 1. Generar 10 bloques adicionales.
bitcoin-cli generatetoaddress 10 "$miner_address" &> /dev/null
# 2. Difundir la segunda transacción. Confirmarla generando un bloque más.
bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$tx_signed"
empleador_balance=$(bitcoin-cli -rpcwallet=Empleador getbalance)
# 3. Informar el saldo de `Empleador`.
echo "Saldo del Empleador: $empleador_balance BTC"
bitcoin-cli stop