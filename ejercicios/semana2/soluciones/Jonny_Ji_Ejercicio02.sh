#!/bin/bash

# ¡Bitcoin core está instalado y configurado con exito!
echo -e "\n# Script de ejecución para el ejercicio 2\n"
echo -e "¡Bitcoin core debe estar instalado y configurado con exito!\n"
echo -e "# Verificar el estado de Bitcoin Core y la cadena\n"

# Escribir el comando getblockchaininfo para ver los datos de la red y la altura de la cadena, debe mostrar la red 'regtest', bloque '0'
bitcoin-cli getblockchaininfo |jq

echo -e "\n# Altura de Bloque"
bitcoin-cli getblockcount

echo -e "\n# Generar y cargar dos nuevas wallets"
echo -e "\n - Crear una billetera llamada Miner"
bitcoin-cli -named createwallet wallet_name="Miner" descriptors=false

echo -e "\n - Crear una billetera llamada Trader"
bitcoin-cli -named createwallet wallet_name="Trader" descriptors=false

echo -e "\n# Verificar que las billeteras esten cargadas con el comando 'listwallets'"
bitcoin-cli listwallets

echo -e "\n# Fondear la billetera Miner con al menos 150 BTC"
bitcoin-cli -rpcwallet=Miner -generate 103

echo -e "\n# Verificar el saldo de la billetera Miner"
bitcoin-cli -rpcwallet=Miner getbalance

echo -e "\n# Crear una transacción desde Miner a Trader que llamaremos 'Parent'"
echo -e "\n# Preparar los datos para crear la transacción"
echo -e "\n# Identificar dos UTXO de 50 BTC cada uno con sus Txid y vout correspondientes en la billetera Miner\n"
Txid1=$(bitcoin-cli -rpcwallet=Miner listunspent |jq -r '[.[] | select(.amount>=50)] | sort_by(.confirmations) | .[0].txid')
vout1=$(bitcoin-cli -rpcwallet=Miner listunspent |jq -r '[.[] | select(.amount>=50)] | sort_by(.confirmations) | .[0].vout')
Txid2=$(bitcoin-cli -rpcwallet=Miner listunspent |jq -r '[.[] | select(.amount>=50)] | sort_by(.confirmations) | .[1].txid')
vout2=$(bitcoin-cli -rpcwallet=Miner listunspent |jq -r '[.[] | select(.amount>=50)] | sort_by(.confirmations) | .[1].vout')

echo "Txid1=$Txid1"
echo "vout1=$vout1"
echo -e "\nTxid2=$Txid2"
echo "vout2=$vout2"

echo -e "\n# Generar una dirección de Gasto en la wallet Trader para recibir 70 BTC"
Gasto=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Gasto")

echo "Gasto=$Gasto"

echo -e "\n# Generar una dirección de Cambio en la wallet Miner para recibir 29.99999 BTC"
Cambio=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Cambio")

echo "Cambio=$Cambio"

echo -e "\n - Enviar a la dirección de Gasto 70 BTC para Trader"
echo -e "\n - Enviar a la dirección de Cambio 29.99999 BTC para Miner"
echo -e "\n - Activar RBF (Habilitar RBF para la transacción)"

echo -e "\n# Crear la transacción con el comando 'createrawtransaction'\n "
TxHex_Parent=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$Txid1'","vout": '$vout1'}, {"txid": "'$Txid2'","vout": '$vout2'}]''' '''[{"'$Gasto'": 70.0000}, {"'$Cambio'": 29.99999}]''' 0 true)

echo "$TxHex_Parent"

echo -e "\n# Verificando la transacción con el comando 'decoderawtransaction':"
bitcoin-cli decoderawtransaction $TxHex_Parent |jq

echo -e "\n# Firmamos la transacción con el comando 'signrawtransactionwithwallet':"
signed_Parent=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $TxHex_Parent |jq -r '.hex')

echo -e "\nhex:$signed_Parent"

echo -e "\n# Correr el comando 'decoderawtransaction' a la Tx firmada y se verán los campos de 'txinwitness'"
bitcoin-cli decoderawtransaction $signed_Parent |jq -r '.vin[].txinwitness'

echo -e "\n#  Enviar la transacción a la red de bitcoin, para esto usamos el comando 'sendrawtransaction':"
Txid_Parent=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_Parent)

echo -e "\nTxid=$Txid_Parent"

echo -e "\n - Podemos revisar la transacción ya enviada con el comando 'getrawtransaction'"
bitcoin-cli getrawtransaction $Txid_Parent 1 |jq

echo -e "\n# Realizar consultas al mempool del nodo para obtener los detalles de la transacción Parent"
echo -e "\n - Crear una variable JSON con los datos de input, output, fees y peso de la Tx"
Miner_Txid=$(bitcoin-cli getrawmempool | jq -r '.[]')

datos_inputs=$(bitcoin-cli getrawtransaction $Miner_Txid 1 |jq -r '.vin | [.[] | {txid: .txid, vout: .vout}]')

datos_outputs=$(bitcoin-cli getrawtransaction $Miner_Txid 1 |jq '.vout | [.[] | {script_pubkey: .scriptPubKey, amount: .value}]')

Fees=$(bitcoin-cli getmempoolinfo | jq -r '.total_fee')

Weight=$(bitcoin-cli getmempoolentry $Miner_Txid | jq '.vsize')

echo -e "\n# Imprimir el JSON en la terminal"
JSON=$(jq -n \
  --argjson input "$datos_inputs" \
  --argjson output "$datos_outputs" \
  --arg fees "$Fees" \
  --arg weight "$Weight" \
  '{
    input: $input,
    output: $output,
    Fees: ($fees | tonumber),
    Weight: ($weight | tonumber)
  }')
echo $JSON | jq

echo -e "\n# Crear una nueva Tx que gaste la transacción Parent. Llamémosla transacción Child"
echo -e "\n - Entrada: Salida de Cambio de la transacción Parent"
echo -e "\n - Salida: Nueva dirección de Miner para enviar 29.99998 BTC"
echo -e "\n# Crear la Tx Child para enviar"
Child_Add=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Child_CPFP")

TxHex_Child=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$Txid_Parent'","vout": 1}]''' '''[{"'$Child_Add'": 29.99998}]''' 0 true)

echo "$TxHex_Child"

echo -e "\n# Firmamos la transacción Child:"
signed_Child=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $TxHex_Child |jq -r '.hex')

echo -e "\nhex:$signed_Child"

echo -e "\n#  Enviar la transacción Child a la red:"
Txid_Child=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_Child)

echo -e "\nTxid=$Txid_Child"

echo -e "\n# Realizar una consulta getmempoolentry para la transacción Child y mostrar la salida"
bitcoin-cli getmempoolentry $Txid_Child |jq

echo -e "\n# Al revisar la mempool se pueden ver las dos transacciones: Parent y Child"
bitcoin-cli getrawmempool |jq

echo -e "\n# Ahora, creamos manualmente una transacción conflictiva que tenga las mismas entradas que la transacción Parent"
echo -e "\n- Ajustamos los valores para aumentar la tarifa de la transacción Parent en 10,000 satoshis"

TxHex_Parent2=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '''[{"txid": "'$Txid1'","vout": '$vout1'}, {"txid": "'$Txid2'","vout": '$vout2'}]''' '''[{"'$Gasto'": 70.0000}, {"'$Cambio'": 29.9998}]''' 0 true)

signed_Parent2=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $TxHex_Parent2 |jq -r '.hex')

Txid_Parent2=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_Parent2)

echo -e "\nTxid_Parent2=$Txid_Parent2"

echo -e "\n# Volvemos a revisar la mempool"
bitcoin-cli getrawmempool |jq

echo -e "\n Podemos ver que solo se encuentra la nueva Tx Parent y la Tx Child ya no existe"
echo -e "\n# Realizamos otra consulta getmempoolentry para la transacción Child y mostramos el resultado en pantalla"
bitcoin-cli getmempoolentry $Txid_Child |jq

echo -e "\n# Explicación del Ejercicio:"
echo " Se creó una transacción Parent con RBF habilitado, se firma y se envia a la red"
echo " Se creó una transacción Child con CPFP para aumentar los fee"
echo " Se reemplazó la transacción Parent con una nueva versión de iguales entradas y diferentes salidas y con mayor fee"
echo " Al revisar la Mempool del nodo, se observa que la transacción Child desapareció"
echo " La nueva Tx Parent invalidó la transacción Child, ya que su Tx de origen ya no existe en el mempool"
echo " Conclusión: RBF y CPFP no pueden usarse simultáneamente, porque al remplazar la Tx original se elimina la Tx descendente"

cat <<"EOF"

[+]	¡Fin del ejercicio 2!"

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
