#!/bin/bash

# ¡Bitcoin core está instalado y configurado con exito!
echo -e "\n# Script de ejecución para el ejercicio 1\n"
echo -e "¡Bitcoin core está instalado y configurado con exito!\n"
echo -e "Verificar el estado de Bitcoin Core\n"

# Escribir el comando getblockchaininfo para ver los datos de la red y la altura de la cadena, debe mostrar la red 'regtest', bloque '0'
bitcoin-cli getblockchaininfo |jq

echo -e "\nAltura de Bloque"
bitcoin-cli getblockcount

# Generar dos nuevas carteras
echo -e "\nCrear una billetera llamada Miner"
bitcoin-cli -named createwallet wallet_name="Miner" descriptors=false

echo -e "\nCrear una billetera llamada Trader"
bitcoin-cli -named createwallet wallet_name="Trader" descriptors=false

echo -e "\nVer los detalles de la billetera Miner"
bitcoin-cli -rpcwallet=Miner getwalletinfo |jq

echo -e "\nVer los detalles de la billetera Trader"
bitcoin-cli -rpcwallet=Trader getwalletinfo |jq

# Generar una dirección
echo -e "\nCrear una nueva dirección en la wallet 'Miner' para recibir "
bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria"

echo -e "\n# Copiar la dirección 'Recompensa de Minería' "
echo -e "\nIngresa la dirección que acabas de copiar"
read Recompensa
echo -e "\n# Minar a la nueva dirección"
bitcoin-cli -rpcwallet=Miner generatetoaddress 101 $Recompensa

echo -e "\nVerificar el estado de la cadena"
echo "Altura de Bloque"
bitcoin-cli getblockcount

echo -e "\nVer los detalles de la billetera Miner"
bitcoin-cli -rpcwallet=Miner getwalletinfo |jq

echo -e "\nVer el balance de la billetera Miner"
bitcoin-cli -rpcwallet=Miner getbalance

echo -e "\nPodemos identificar los UTXO disponibles"
echo "# Podemos ver detalles como 'txid', 'vout', 'address', 'label', 'scripttpubkey', 'amount', 'confirmations'"
bitcoin-cli -rpcwallet=Miner listunspent |jq

echo -e "\n¿Cuántos bloques se necesitan para obtener un saldo positivo? "
echo "Se necesitan 100 bloques confirmados para que el saldo de la billetera se muestre positivo"
echo -e "\n¿Por qué el saldo de la billetera se comporta así? "
echo "El saldo de cada bloque minado necesita 100 bloques para estar disponible para ser gastado, se le denomina a madurar el saldo o madurar la tx coinbase."

echo -e "\nBalance de la billetera Miner"
bitcoin-cli -rpcwallet=Miner getbalance

# Hacer una transacción
echo -e "\n# Crear una dirección receptora con la etiqueta 'Recibido' en la billetera Trader."
bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido"

echo -e "\n# Copiar la dirección 'Recibido' "
echo -e "\nIngresa la dirección que acabas de copiar"
read Recibido
echo -e "\n# Enviar una transacción que pague 20 BTC desde la billetera Miner a la billetera Trader." 
echo -e "\nTxid= "
bitcoin-cli -rpcwallet=Miner sendtoaddress $Recibido 20.000

echo -e "\n# Copiar el TxId de la transacción que se acaba de enviar"
echo -e "\nObtener la transacción no confirmada desde el 'mempool' del nodo y mostrar el resultado"
echo -e "\nIngresa el Txid que acabas de copiar"
read TxId
bitcoin-cli getmempoolentry $TxId |jq

echo -e "\nMinar un bloque para que la transacción se confirme"
bitcoin-cli -rpcwallet=Miner -generate 1

echo -e "\n# Obtener los detalles de la transacción y mostrarlos en la terminal:"
bitcoin-cli getrawtransaction $TxId 1 |jq

cat <<"EOF"

[+]	¡Fin del ejercicio 1!"

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
