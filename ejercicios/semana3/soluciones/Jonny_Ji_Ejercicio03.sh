#!/bin/bash

# ¡Bitcoin core debe estár instalado y configurado con exito!

# EJERCICIO 3
echo -e "\n# Script de ejecución para el ejercicio 3\n"
echo -e "¡Bitcoin core debe estar instalado y configurado con exito!\n"
echo -e "# Verificando el estado de Bitcoin Core y la cadena\n"

# Verificar que Bitcoin Core está corriendo en regtest
bitcoin-cli getblockchaininfo |jq

# Altura de Bloque
Altura_de_bloque=$(bitcoin-cli getblockcount)
echo -e "\nAltura_de_bloque= $Altura_de_bloque"

# Crear tres monederos: Miner, Alice y Bob
# Fondear los monederos generando algunos bloques para Miner y luego enviando algunas monedas a Alice y Bob
echo -e "\n# Crear tres monederos: Miner, Alice y Bob"

bitcoin-cli -named createwallet wallet_name="Miner"

bitcoin-cli -named createwallet wallet_name="Alice" 

bitcoin-cli -named createwallet wallet_name="Bob" 

echo -e "\n# Fondear la wallet Miner"

bitcoin-cli -rpcwallet=Miner -generate 103 >/dev/null

echo -e "\n# verificar el balance en Miner"
balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo -e "\nbalance=$balance"

echo -e "\n# Crear una Tx para enviar algunas monedas a Alice y Bob"

Alice_Addr=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Alice")

Bob_Addr=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Bob")

Txid_AB=$(bitcoin-cli -rpcwallet=Miner sendmany "" "{\"$Alice_Addr\":20,\"$Bob_Addr\":20}")

echo -e "\n Txid_AB=$Txid_AB"
echo -e "\n# Minar un bloque para confirmar la transacción"

bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

echo -e "\n# Verificar el saldo en las tres wallets"

balance_Miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
balance_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_Bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo "balance_Miner=$balance_Miner"
echo "balance_Alice=$balance_Alice"
echo "balance_Bob=$balance_Bob"

# Crear un wallet Multisig 2-de-2 combinando los descriptors de Alice y Bob. Uilizar la funcion "multi" wsh(multi(2,descAlice,descBob) para crear un "output descriptor". Importar el descriptor al Wallet Multisig. Generar una direccion.
echo -e "\n# Crear una wallet multifirma 'Multisig' 2-de-2"

bitcoin-cli -named createwallet wallet_name="Multisig" disable_private_keys=true blank=true

echo "# Configurar Multisig"
echo "# Crear el descriptor segwit para la wallet Multisig con los descriptors de las wallets Alice y Bob"

Alice_xpub_ext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')

Alice_xpub_int=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')

Bob_xpub_ext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')

Bob_xpub_int=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')

# Descriptores sumarios para cuentas externa (recepción) e interna (cambio)
Descr_Sum_Ext=$(bitcoin-cli getdescriptorinfo "wsh(multi(2,$Alice_xpub_ext,$Bob_xpub_ext))" | jq -r '.descriptor')
Descr_Sum_Int=$(bitcoin-cli getdescriptorinfo "wsh(multi(2,$Alice_xpub_int,$Bob_xpub_int))" | jq -r '.descriptor')

# Importa ambos descriptores
Multi_Descr=$(jq -n "[\
  {\"desc\":\"$Descr_Sum_Ext\",\"active\":true,\"internal\":false,\"timestamp\":\"now\"},\
  {\"desc\":\"$Descr_Sum_Int\",\"active\":true,\"internal\":true,\"timestamp\":\"now\"}\
]")

# Activar los descriptors en la wallet Multisig
bitcoin-cli -rpcwallet=Multisig importdescriptors "$Multi_Descr" >/dev/null

# Generar la primera dirección multifirma
First_MultiADDr=$(bitcoin-cli -rpcwallet=Multisig getnewaddress)

echo -e "\n# Primera dirección multisig generada: $First_MultiADDr"
echo -e "\n# Información de la dirección"

bitcoin-cli -named -rpcwallet=Multisig getaddressinfo address=$First_MultiADDr |jq

echo -e "\n# Fondear la wallet Multisig con 10 BTC de Alice y 10 BTC de Bob"
echo "# Preparar los datos para construir la Tx de fondeo a la wallet Multisig"
echo "# Seleccionar los inputs de Alice y Bob, seleccionar la dirección de destino"

Alice_input=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].txid')
Alice_vout=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].vout')
Bob_input=$(bitcoin-cli -rpcwallet=Bob listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].txid')
Bob_vout=$(bitcoin-cli -rpcwallet=Bob listunspent |jq -r '[.[]] | sort_by(.confirmations) | .[0].vout')
Alice_changeADDr=$(bitcoin-cli -rpcwallet=Alice getrawchangeaddress)
Bob_changeADDr=$(bitcoin-cli  -rpcwallet=Bob   getrawchangeaddress)

echo -e "\nAlice_input=$Alice_input"
echo "Alice_vout=$Alice_vout"
echo -e "\nBob_input=$Bob_input"
echo "Bob_vout=$Bob_vout"
echo -e "\nAlice_changeADDr=$Alice_changeADDr"
echo "Bob_changeADDr=$Bob_changeADDr"

# Generar la primera dirección multifirma

Multi_ADDr=$First_MultiADDr

echo -e "\nMulti_ADDr=$Multi_ADDr"

echo -e "\n# Contruir la Tx PSBT de fondeo para la Multisig"

psbt_Fondeo=$(bitcoin-cli -named createpsbt inputs='[ { "txid": "'$Alice_input'", "vout": '$Alice_vout' }, { "txid": "'$Bob_input'", "vout": '$Bob_vout' } ]' outputs='[ { "'$Multi_ADDr'": 20.00000 }, { "'$Alice_changeADDr'": 9.99999 }, { "'$Bob_changeADDr'": 9.99999 } ]''')

# Firmar la PSBT con las wallets Alice y Bob
psbt_firmaALICE=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbt_Fondeo" | jq -r '.psbt')
psbt_firmaBOB=$(bitcoin-cli -rpcwallet=Bob   walletprocesspsbt "$psbt_firmaALICE" | jq -r '.psbt')

# Finalizar la PSBT de fondeo
Txhex_PSBT=$(bitcoin-cli finalizepsbt "$psbt_firmaBOB" | jq -r '.hex')

# Transmitir al Tx a la red
Txid_psbtFondeo=$(bitcoin-cli sendrawtransaction "$Txhex_PSBT")

echo -e "\nTxid_psbtFondeo: $Txid_psbtFondeo"

echo -e "\n# Generar un nuevo bloque para confirmar la transacción"
bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

echo -e "\n# Verificar el balance de las billeteras"
balance_Multisig=$(bitcoin-cli -rpcwallet=Multisig getbalance)
balance_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_Bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo "balance_Multisig=$balance_Multisig"
echo "balance_Alice=$balance_Alice"
echo -e "balance_Bob=$balance_Bob\n"

echo "# Liquidar Multisig"
echo "# Crear una PSBT para gastar fondos del wallet Multisig"
echo "# Enviar 3 BTC a la wallet Alice"

# Genera una dirección de destino para Alice
Alice_newAddr=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Recibir Multisig")

echo -e "\nAlice_newAddr=$Alice_newAddr"

echo -e "\n# Contruir la Tx PSBT de la wallet Multisig para pagar a Alice"

psbt_pagaAlice=$(bitcoin-cli -rpcwallet=Multisig walletcreatefundedpsbt '[]' '[{"'$Alice_newAddr'":3}]' 0 '{"includeWatching":true}' true | jq -r '.psbt')

# Firmar la PSBT por Alice y Bob
psbt_firmALICE=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbt_pagaAlice" | jq -r '.psbt')
psbt_firmBOB=$(bitcoin-cli -rpcwallet=Bob   walletprocesspsbt "$psbt_firmALICE" | jq -r '.psbt')

Txhex_pagaAlice=$(bitcoin-cli finalizepsbt "$psbt_firmBOB" | jq -r '.hex')

# Finaliza la PSBT y enviar la Tx PSBT que paga a Alice a la red
Txid_pagaAlice=$(bitcoin-cli sendrawtransaction "$Txhex_pagaAlice")

echo "Txid_pagaAlice: $Txid_pagaAlice"

echo -e "\n# Minar un bloque para confirmar la transacción que envía los 3 BTC de Multisig a Alice"

bitcoin-cli -rpcwallet=Miner -generate 1 >/dev/null

echo -e "\n# Verificar el balance de las billeteras"
echo -e "\n# Imprimir los saldos finales de Alice y Bob"

balance_Multisig=$(bitcoin-cli -rpcwallet=Multisig getbalance)
balance_Alice=$(bitcoin-cli -rpcwallet=Alice getbalance)
balance_Bob=$(bitcoin-cli -rpcwallet=Bob getbalance)

echo "balance_Multisig=$balance_Multisig"
echo "balance_Alice=$balance_Alice"
echo "balance_Bob=$balance_Bob"

# FIN DEL EJERCICIO

cat <<"EOF"

[+]	¡Fin del ejercicio 3!"

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
