#!/bin/bash

# ¡Bitcoin core debe estár instalado y configurado con exito!

# EJERCICIO 4
echo -e "\n# Script de ejecución para el ejercicio 4\n"
echo -e "¡Bitcoin core debe estar instalado y configurado con exito!\n"
echo -e "# Verificando el estado de Bitcoin Core y la cadena"

# Verificar que Bitcoin Core está corriendo en regtest
Red=$(bitcoin-cli getblockchaininfo |jq -r '.chain')
echo -e "\nRed = $Red"

# Altura de Bloque
Altura_de_bloque=$(bitcoin-cli getblockcount)
echo -e "\nAltura de bloque = $Altura_de_bloque"

# Crear tres monederos: Miner, Empleador y Empleado
echo -e "\n# Crear tres monederos: Miner, Empleador y Empleado"

bitcoin-cli -named createwallet wallet_name="Miner"

bitcoin-cli -named createwallet wallet_name="Empleador" 

bitcoin-cli -named createwallet wallet_name="Empleado" 

# Generar algunos bloques para Fondear los monederos Miner y enviar algunas monedas a la wallet Empleador.
echo -e "\n# Fondear la wallet Miner"

bitcoin-cli -rpcwallet=Miner -generate 103 >/dev/null

# Enviando algunas monedas a Empleador
echo -e "\n# Crear una Tx para enviar algunas monedas a la wallet Empleador"

Empleador_Addr=$(bitcoin-cli -rpcwallet=Empleador getnewaddress "Empleador")

bitcoin-cli -rpcwallet=Miner sendtoaddress $Empleador_Addr 65.000

# Minar un bloque para confirmar la transacción

bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

# Verificar el saldo en la wallet Empleador
echo -e "\nVerificar el saldo en la wallet Empleador"

balance_Empleador=$(bitcoin-cli -rpcwallet=Empleador getbalance)
echo -e "\nbalance Empleador = $balance_Empleador BTC"

# - Configurar un contrato Timelock
# Crea una transacción de salario donde el Empleador paga al Empleado 40 BTC.
# Agrega un timelock absoluto de 500 bloques para la transacción.

echo -e "\n# *Configurar una transacción con Timelock*"
echo -e "\n# Crea una transacción de salario donde el Empleador paga al Empleado 40 BTC."
echo "# Agrega un timelock absoluto de 500 bloques para la transacción."

# Preparar los datos para construir la Tx donde el Empleador paga al Empleado.
# Seleccionar los inputs de la wallet Empleador.
# Generar una dirección para recibir en la wallet Empleado.

Empleador_input=$(bitcoin-cli -rpcwallet=Empleador listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].txid')
Empleador_vout=$(bitcoin-cli -rpcwallet=Empleador listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].vout')
Empleador_changeADDr=$(bitcoin-cli -rpcwallet=Empleador getrawchangeaddress)
Empleado_ADDr=$(bitcoin-cli -rpcwallet=Empleado getnewaddress "Sueldo")

pago_Empleado=$(bitcoin-cli -rpcwallet=Empleador createrawtransaction '''[{"txid": "'$Empleador_input'","vout": '$Empleador_vout'}]''' '''[{"'$Empleado_ADDr'": 40.0000}, {"'$Empleador_changeADDr'": 24.99999}]''' 500 true )

echo -e "\nTransacción de pago al Empleado = $pago_Empleado"

echo -e "\n# Firmamos la transacción:"
sueldo_Empleado=$(bitcoin-cli -rpcwallet=Empleador signrawtransactionwithwallet "$pago_Empleado" | jq -r '.hex')

echo -e "\n# Enviar la transacción a la red"
bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$sueldo_Empleado"

echo -e "\n# Hay un mensaje de error al tratar de enviar la transacción con el timelock"

echo -e "\n# Minar hasta el bloque 500 y volver a transmitir la transacción."
bitcoin-cli -rpcwallet=Miner -generate 398 >/dev/null

Txid_pago=$(bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$sueldo_Empleado")
echo -e "\n# La transacción se envía con exito después de minar los 500 bloques"
echo -e "\nTxid = $Txid_pago"

# Generar un nuevo bloque para confirmar la transacción
bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

echo -e "\n# Imprimir los saldos de las wallets Empleado y Empleador"

balance_Empleador=$(bitcoin-cli -rpcwallet=Empleador getbalance)
balance_Empleado=$(bitcoin-cli -rpcwallet=Empleado getbalance)

echo -e "\nbalance_Empleador = $balance_Empleador BTC"
echo "balance_Empleado = $balance_Empleado BTC"

# - Gastar desde el Timelock
# Crear una Tx de gasto en la que el Empleado gaste los fondos a una nueva dirección del monedero Empleado.
# Agrega una salida OP_RETURN en la Tx de gasto con los datos de cadena "He recibido mi salario, ahora soy rico".

echo -e "\n# *Gastar desde el Timelock*"
echo -e "\n# Crear una Tx de gasto en la que el Empleado gaste los fondos a una nueva dirección propia de su monedero."
echo -e "\n# Agregar una salida OP_RETURN en la Tx de gasto con los datos de cadena 'He recibido mi salario, ahora soy rico'."

# Preparar los datos para construir la Tx donde el Empleado agrega una salida OP_RETURN.
# Seleccionar los inputs de la wallet Empleado.
# Generar una dirección para recibir en la wallet Empleado.
# Covertir el texto para el OP_RETURN en hexadecimal

Empleado_input=$(bitcoin-cli -rpcwallet=Empleado listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].txid')
Empleado_vout=$(bitcoin-cli -rpcwallet=Empleado listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].vout')
Empleado_newADDr=$(bitcoin-cli -rpcwallet=Empleado getnewaddress "Salario")
opreturn_data=$(printf "He recibido mi salario, ahora soy rico" | xxd -p | tr -d '\n')

Gasto_Empleado=$(bitcoin-cli -named -rpcwallet=Empleado createrawtransaction inputs='[ { "txid": "'$Empleado_input'", "vout": '$Empleado_vout' } ]' outputs='{ "data": "'$opreturn_data'", "'$Empleado_newADDr'": 39.99999 }')

Tx_Gasto=$(bitcoin-cli -rpcwallet=Empleado signrawtransactionwithwallet "$Gasto_Empleado" | jq -r '.hex')

echo -e "\nTx de Gasto = $Tx_Gasto"

echo -e "\n# Extrae y transmite la transacción completamente firmada."
Txid_Gasto=$(bitcoin-cli -rpcwallet=Empleador sendrawtransaction "$Tx_Gasto")

echo -e "\ntxid con OP_RETURN = $Txid_Gasto"

echo -e "\n# Inspeccionar la transacción y el OP_RETURN"

bitcoin-cli getrawtransaction "$Txid_Gasto" 1 | jq '.vout[] | select(.scriptPubKey.type == "nulldata") | .scriptPubKey.asm'

echo -e "\n# Copiar el OP_RETURN para verificar el mensaje"
echo -e "\nIngresa el OP_RETURN que acabas de copiar"
read OP_RETURN
echo -e "\n# Descifrar el mensaje en el OP_RETURN"
echo -n "$OP_RETURN" | xxd -r -p
echo -e "\n"

# Generar un nuevo bloque para confirmar la transacción
bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

echo "# Imprimir los saldos finales del Empleado y Empleador"

balancefinal_Empleador=$(bitcoin-cli -rpcwallet=Empleador getbalance)
balancefinal_Empleado=$(bitcoin-cli -rpcwallet=Empleado getbalance)

echo -e "\nbalance final Empleador = $balancefinal_Empleador BTC"
echo "balance final Empleado = $balancefinal_Empleado BTC"

echo -e "\n# FIN DEL EJERCICIO"

cat <<"EOF"

[+]	¡Fin del ejercicio 4!"

        ⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀
        ⣿⣿⣿⣿⠟⠿⠿⡿⠀⢰⣿⠁⢈⣿⣿⣿⣿⣿⠀⠀
        ⣿⣿⣿⣿⣤⣄⠀⠀⠀⠈⠉⠀⠸⠿⣿⣿⣿⣿⠀
        ⣿⣿⣿⣿⣿⡏⠀⠀⢠⣶⣶⣤⡀⠀⠈⢻⣿⣿
        ⣿⣿⣿⣿⣿⠃⠀⠀⠼⣿⣿⡿⠃⠀⠀⢸⣿⣿
        ⣿⣿⣿⣿⡟⠀⠀⢀⣀⣀⠀⠀⠀⠀⢴⣿⣿⣿
        ⣿⣿⢿⣿⠁⠀⠀⣼⣿⣿⣿⣦⠀⠀⠈⢻⣿⣿
        ⣿⣏⠀⠀⠀⠀⠀⠛⠛⠿⠟⠋⠀⠀⠀⣾⣿⣿
        ⣿⣿⣿⣿⠇⠀⣤⡄⠀⣀⣀⣀⣀⣠⣾⣿⣿⣿⠀
        ⣿⣿⣿⣿⣄⣰⣿⠁⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀
        ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀v25.0⠀⠀⠀⠀⠀⠀⠀

[+] ¡Librería de Satoshi!
[+]	¡Bitcoin from Command Line!
EOF

