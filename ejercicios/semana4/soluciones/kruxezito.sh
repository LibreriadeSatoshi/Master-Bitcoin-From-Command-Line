#!/bin/bash

#-----------COPIE MI INICIALIZACION DEL BITCOIND-----------

btr_cli="bitcoin-cli -conf=$HOME/.bitcoin/bitcoin.conf"

# Stop a Bitcoind para no tener problema al inicialiarlo.
$btr_cli stop &> /dev/null

sleep 3

# Remove a Regtest para Comenzar desde 0.
if [[ "$OSTYPE" == "darwin"* ]]; then
	rm -rf ~/Library/Application\ Support/Bitcoin/regtest
else
	rm -rf ~/.bitcoin/regtest/ &> /dev/null
fi

# Inicializando Bitcoind --daemon.
bitcoind -conf="$HOME/.bitcoin/bitcoin.conf" --daemon

sleep 5
# CONFIGURAR UN CONTRATO TIMELOCK

# ------------------------------------------------------------------------

# 1- Crear 3 monederos.
wallets=("Miner" "Empleado" "Empleador")

for wallet in ${wallets[@]}; do
	$btr_cli createwallet $wallet &> /dev/null 
done

# ------------------------------------------------------------------------

# 2- Fondeando los monederos apartir de la generacion de bloques.
miner_address=$($btr_cli -rpcwallet=Miner getnewaddress)

$btr_cli -rpcwallet=Miner generatetoaddress 102 $miner_address &> /dev/null

miner_utxos=($($btr_cli -rpcwallet=Miner listunspent | jq -c '.[] | {txid, vout}'))

first_utxo=$(echo ${miner_utxos[0]} | jq '.')
first_txid=$(echo $first_utxo | jq -r '.txid')
first_vout=$(echo $first_utxo | jq -r '.vout')

empleador_address=$($btr_cli -rpcwallet=Empleador getnewaddress)

unsigned_tx=$($btr_cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$first_txid'", "vout": '$first_vout'}]''' '''{"'$empleador_address'": 49.9999}''')
signed_tx_hex=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $unsigned_tx | jq -r '.hex')
miner_txid=$($btr_cli -rpcwallet=Miner sendrawtransaction $signed_tx_hex)

$btr_cli -rpcwallet=Miner generatetoaddress 1 $miner_address &> /dev/null

# ------------------------------------------------------------------------

# 3- Creando una transaccion donde paga el Empleador al Empleado.
empleador_utxos=($($btr_cli -rpcwallet=Empleador listunspent | jq -c '.[] | {txid, vout}'))
empleador_outpoint_txid=$(echo $empleador_utxos | jq -r '.txid')
empleador_outpoint_vout=$(echo $empleador_utxos | jq -r '.vout')

empleado_address=$($btr_cli -rpcwallet=Empleado getnewaddress)
empleador_change_address=$($btr_cli -rpcwallet=Empleador getrawchangeaddress)

# ------------------------------------------------------------------------

# 4- Agrega un timelock absoluto de 500 blocks.
empleador_unsigned_tx=$($btr_cli -rpcwallet=Empleador createrawtransaction '''[{"txid": "'$empleador_outpoint_txid'", "vout": '$empleador_outpoint_vout'}]''' '''{"'$empleado_address'": 40, "'$empleador_change_address'": 9.9998}''' 500)
empleador_signed_tx=$($btr_cli -rpcwallet=Empleador signrawtransactionwithwallet $empleador_unsigned_tx | jq -r '.hex')
empleador_txid=$($btr_cli -rpcwallet=Empleador sendrawtransaction $empleador_signed_tx)

# ------------------------------------------------------------------------

# 5- Informar que sucede con la transaccion al momento de querer transmitirla.
# La transaccion sera rechazada por los nodos (no entrara al mempool) hasta que la red alcance el bloque 500. Antes de ese bloque, la transaccion se considera invalida para cualquier minero.

# ------------------------------------------------------------------------

# 6- Minar hasta el Bloque 500 y transmitir la transaccion.
$btr_cli -rpcwallet=Miner generatetoaddress 397 $miner_address &> /dev/null
empleador_txid=$($btr_cli -rpcwallet=Empleador sendrawtransaction $empleador_signed_tx)
$btr_cli -rpcwallet=Miner generatetoaddress 1 $miner_address &> /dev/null

# ------------------------------------------------------------------------

# 7- Imprimir saldos finales del Empleado y Empleador.
echo "================= Empleado Balance ================="
$btr_cli -rpcwallet=Empleado getbalance
echo "================= Empleador Balance ================="
$btr_cli -rpcwallet=Empleador getbalance

# ------------------------------------------------------------------------
# GASTAR DESDE EL TIMELOCK.
# ------------------------------------------------------------------------

# 1- Crear una transaccion de gasto en la que el Empleado gaste los fondos a una nueva direccion de monedero del Empleado.
empleado_utxos=($($btr_cli -rpcwallet=Empleado listunspent | jq -c '.[] | {txid, vout}'))
empleado_outpoint_txid=$(echo $empleado_utxos | jq -r '.txid')
empleado_outpoint_vout=$(echo $empleado_utxos | jq -r '.vout')

# ------------------------------------------------------------------------

# 2- Agregar una salida OP_RETURN en la transaccion de gasto con los datos de cadena "He recibido mi salario, ahora soy rico".
empleado_address2=$($btr_cli -rpcwallet=Empleado getrawchangeaddress)
empleado_unsigned_tx=$($btr_cli -rpcwallet=Empleado createrawtransaction '''[{"txid": "'$empleado_outpoint_txid'", "vout": '$empleado_outpoint_vout'}]''' '''{"data": "486520726563696269646F206D692073616C6172696F2C2061686F726120736F79207269636F", "'$empleado_address2'": 39.9999}''')

# ------------------------------------------------------------------------

# 3- Extrae y transmite la transacción completamente firmada.
empleado_signed_tx=$($btr_cli -rpcwallet=Empleado signrawtransactionwithwallet $empleado_unsigned_tx | jq -r '.hex')
empleado_txid=$($btr_cli -rpcwallet=Empleado sendrawtransaction $empleado_signed_tx)
$btr_cli -rpcwallet=Miner generatetoaddress 1 $miner_address &> /dev/null

# ------------------------------------------------------------------------

# 4- Imprime los saldos finales del Empleado y Empleador.
echo "================= Empleado final balance ================="
$btr_cli -rpcwallet=Empleado getbalance
echo "================= Empleador final balance ================="
$btr_cli -rpcwallet=Empleador getbalance


# ------------------------------------------------------------------------
# CONFIGURAR UN TIMELOCK RELATIVO.
# ------------------------------------------------------------------------

# 1- Crear una transacción en la que Empleador pague 1 BTC a Miner, pero con un timelock relativo de 10 bloques.
empleador_utxos2=($($btr_cli -rpcwallet=Empleador listunspent | jq -c '.[] | {txid, vout}'))
empleador_outpoint_txid2=$(echo $empleador_utxos2 | jq -r '.txid')
empleador_outpoint_vout2=$(echo $empleador_utxos2 | jq -r '.vout')

miner_address2=$($btr_cli -rpcwallet=Miner getnewaddress)
empleador_change_address2=$($btr_cli -rpcwallet=Empleador getrawchangeaddress)
empleador_unsigned_tx2=$($btr_cli -rpcwallet=Empleador createrawtransaction '''[{"txid": "'$empleador_outpoint_txid2'", "vout": '$empleador_outpoint_vout2', "sequence": 10}]''' '''{"'$miner_address2'": 1, "'$empleador_change_address2'": 8.9997}''')
empleador_signed_tx2=$($btr_cli -rpcwallet=Empleador signrawtransactionwithwallet $empleador_unsigned_tx2 | jq -r '.hex')

# ------------------------------------------------------------------------

# 2- Informar en la salida del terminal qué sucede cuando intentas difundir la transacción.
echo "----------------------------------------------------------------------------"
echo "INFO: Intentando enviar transacción con Timelock Relativo (10 bloques)..."
echo "Explicación: Aun no se puede enviar esta transaccion por que outpoint utilizado en el Input deberia alcanzar una madurez de minimo 10 bloques de profundidad."
$btr_cli -rpcwallet=Empleador sendrawtransaction $empleador_signed_tx2 2>&1

# ------------------------------------------------------------------------
# GASTAR DESDE EL TIMELOCK RELATIVO.
# ------------------------------------------------------------------------

# 1- Generar 10 bloques adicionales.
$btr_cli -rpcwallet=Miner generatetoaddress 10 $miner_address &> /dev/null

# ------------------------------------------------------------------------

# 2- Difundir la segunda transacción. Confirmarla generando un bloque más.
$btr_cli -rpcwallet=Empleador sendrawtransaction $empleador_signed_tx2 &> /dev/null
$btr_cli -rpcwallet=Miner generatetoaddress 1 $miner_address &> /dev/null

# ------------------------------------------------------------------------

# 3- Informar saldo del Empleador.
echo "================= Empleador final balance ================="
$btr_cli -rpcwallet=Empleador getbalance
