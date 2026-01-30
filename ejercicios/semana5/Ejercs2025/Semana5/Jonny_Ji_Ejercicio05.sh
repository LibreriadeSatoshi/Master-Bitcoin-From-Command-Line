#!/bin/bash

# ¡Bitcoin core debe estár instalado y configurado con exito!

# EJERCICIO 5
echo -e "\n# Script de ejecución para el ejercicio 5\n"
echo -e "¡Bitcoin core debe estar instalado y configurado con exito!\n"
echo -e "# Verificando el estado de Bitcoin Core y la cadena"

# Verificar que Bitcoin Core está corriendo en regtest
Red=$(bitcoin-cli getblockchaininfo |jq -r '.chain')
echo -e "\nRed = $Red"

# Altura de Bloque
Altura_de_bloque=$(bitcoin-cli getblockcount)
echo -e "\nAltura de bloque = $Altura_de_bloque"

# Crear dos billeteras: Miner, Alice.
echo -e "\n# Crear dos monederos: Miner y Alice"

bitcoin-cli -named createwallet wallet_name="Miner"

bitcoin-cli -named createwallet wallet_name="Alice" 

# Fondear las billeteras generando algunos bloques para Miner y enviando algunas monedas a Alice.

echo -e "\n# Fondear la wallet Miner"
bitcoin-cli -rpcwallet=Miner -generate 101 >/dev/null

# Enviando algunas monedas a Alice
echo -e "\n# Crear una Tx para enviar algunas monedas a la wallet de Alice"

Alice_Addr=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Fondeo")

bitcoin-cli -rpcwallet=Miner sendtoaddress $Alice_Addr 35.000

echo -e "\n# Confirmar la transacción y chequear que Alice tiene un saldo positivo."

bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

saldo_positivo=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].amount')

balance_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)

echo "balance Alice  = $balance_Alice BTC"
echo "saldo gastable = $saldo_positivo BTC"

echo -e "\n*Configurar un timelock relativo*"
echo -e "\n# Crear una transacción en la que Alice pague 10 BTC al Miner, pero con un timelock relativo de 10 bloques."
echo -e "\n# Primero, hay que determinar la altura actual del bloque y la altura del bloque destino."

count=$(bitcoin-cli getblockcount)
echo -e "\nAltura de bloque actual = $count"
echo -e "\nIngresa el timelock relativo en bloques"
read tiempobloqueo

num1=$count
num2=$tiempobloqueo
blockcount=$((num1 + num2))
echo -e "\nEl Timelock relativo de 10 bloques se cumple en el bloque = $blockcount"

echo -e "\n# Preparar los datos para construir la Tx donde Alice paga a Miner."
# Seleccionar los inputs de la wallet Alice.
# Generar una dirección para recibir en la wallet Miner.

Alice_input=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].txid')
Alice_vout=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].vout')
Alice_changeADDr=$(bitcoin-cli -rpcwallet=Alice getrawchangeaddress)
Miner_ADDr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Pago")

pago_Miner=$(bitcoin-cli -rpcwallet=Alice createrawtransaction "[{\"txid\":\"$Alice_input\",\"vout\":$Alice_vout,\"sequence\":"$tiempobloqueo"}]" "[{\"$Alice_changeADDr\":24.99999}, {\"$Miner_ADDr\":10}]")
echo -e "\nTx que paga a Miner con timelock de 10 bloques = $pago_Miner"

echo -e "\nFirmar la transacción y enviar a la red."
# Firmamos la transacción:
send_Miner=$(bitcoin-cli -rpcwallet=Alice signrawtransactionwithwallet "$pago_Miner" | jq -r '.hex')

# Enviar la transacción a la red
bitcoin-cli -rpcwallet=Alice sendrawtransaction "$send_Miner"

echo -e "\n# Hay un mensaje de error por el timelock relativo en la transacción"

# Informar en la salida del terminal qué sucede cuando intentas difundir la segunda transacción.

echo -e "\n# El error 'no BIP68-final' ocurre porque la transacción intenta gastar una entrada que no ha cumplido con las condiciones de bloqueo de tiempo relativo requerida definida por el BIP68."
echo "# Este error indica que la transacción aún no es definitiva debido a las restricciones del número de secuencia."

echo -e "\n*Gastar desde el timelock relativo*"
echo -e "\n# Generar 10 bloques más y difundir la Tx nuevamente"
# Generar 10 bloques adicionales.
bitcoin-cli -rpcwallet=Miner -generate 10 >/dev/null

# Altura de Bloque
Altura=$(bitcoin-cli getblockcount)
echo -e "\nAltura de bloque actual = $Altura"

echo -e "\n# Difundir la segunda transacción."
bitcoin-cli -rpcwallet=Alice sendrawtransaction "$send_Miner"

echo -e "\n# Confirmar la Tx generando un bloque más y verificar el saldo en Alice."
bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

# Informar el saldo de Alice.

saldo_gastable=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].amount')

balance_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)

echo -e "\nsaldo positivo = $saldo_gastable BTC"
echo "balance Alice  = $balance_Alice BTC"

# FIN DEL EJERCICIO

cat <<"EOF"

[+]	¡Fin del ejercicio 5!"

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

