#!/bin/bash

# Sube un archivo como este mediante un pull request en la carpeta soluciones, el archivo debe tener tu nombre en discord

# Nombre de archivos, rutas y comandos

bitcoind="../../../../bitcoin-30.2/bin/bitcoind"
BitConf="../../../../bitcoin-30.2/.bitcoin/bitcoin.conf" # Ruta relativa a bitcoin.conf
BitConf_ABS=$(realpath "$BitConf") # Ruta absoluta a bitcoin.conf
bitcoinCli="../../../../bitcoin-30.2/bin/bitcoin-cli"

# Apagar el nodo de bitcoin en caso que se encuentre activo
$bitcoinCli -conf="$BitConf_ABS" stop
sleep 5
# Eliminar el directorio de la regtest 
rm -rf ~/.bitcoin/regtest
echo "Directorio de regtest eliminado"
sleep 2
# Ejecutar Bitcoin Core con la configuración personalizada
# $bitcoind -conf="$BitConf_ABS" -printtoconsole # Con este comando se visualizan los procesos en tiempo real
$bitcoind -regtest -conf="$BitConf_ABS" -daemon # Con este comando se ejecuta en segundo plano

# Creacion de wallets
echo "Creando wallets..."
sleep 1
if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Miner" 2>/dev/null; then
    echo "Wallet 'Miner' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Miner"
else
    echo "Wallet 'Miner' creada exitosamente"
fi

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Alice" 2>/dev/null; then
    echo "Wallet 'Alice' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Alice"
else
    echo "Wallet 'Alice' creada exitosamente"
fi

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Bob" 2>/dev/null; then
    echo "Wallet 'Bob' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Bob"
else
    echo "Wallet 'Bob' creada exitosamente"
fi

# Creando direccion para minero recompensas
AddressMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")
echo "Direccion del Miner: $AddressMiner"

balance=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
echo "Balance del Miner: $balance"

# Minando 101 bloques para obtener la primera recompensa
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 101 "$AddressMiner"

MAX_ITERACIONES=10  # Límite del for

for ((i=1; i<=MAX_ITERACIONES; i++)); do
    echo "Iteración $i: Consultando balance..."
    
    balance=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
    echo "Balance actual: $balance"
    
    if (( $(echo "$balance >= 150" | bc -l) )); then
        echo "¡Balance >= 150 ($balance)! Saliendo del bucle."
        break
    else
        echo "Balance < 150. Minando 1 bloque por vez..."
        $bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$AddressMiner"
        echo "Bloques minados. Esperando confirmaciones..."
        sleep 2  # Pequeña pausa para que se procesen las confirmaciones
    fi
done

# Visualizacion de los UTXO existentes para Miner wallet
listUtxo=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent)

# Captura de las informacion de los txid y vout necesarios 
utxo_txid_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .txid')
utxo_vout_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .vout')
utxo_txid_1=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[1] | .txid')
utxo_vout_1=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[1] | .vout')

# Visualizacion de la informacion capturada
echo $utxo_txid_0
echo $utxo_vout_0
echo $utxo_txid_1
echo $utxo_vout_1

# Genera una direccion de cambio para Miner wallet
changeaddressMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getnewaddress label="Cambio")
echo "Direccion de cambio: $changeaddressMiner"

# Genera una direccion de destino para Alice wallet
destinationaddressAlice=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" -named getnewaddress label="Destino")
echo "Direccion de destino Alice: $destinationaddressAlice"

# Genera una direccion de destino para Bob wallet
destinationaddressBob=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" -named getnewaddress label="Destino")
echo "Direccion de destino Bob: $destinationaddressBob"

# CREAR, FIRMAR Y TRANSMITIR TRANSACCIONES PARA FONDEAR WALLETS

# Crear la transaccion para fondear wallet Alice
rawtxhexAlice=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressAlice'": 20, "'$changeaddressMiner'": 29.99998 }''')
# Firmamos la transaccion Alice
signedtxhexAlice=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhexAlice | jq -r '.hex')
# Transmitimos la transaccion
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexAlice

# Crear la transaccion para fondear wallet Bob
rawtxhexBob=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressBob'": 20, "'$changeaddressMiner'": 29.99998 }''')
# Firmamos la transaccion Bob
signedtxhexBob=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhexBob | jq -r '.hex')
# Transmitimos la transaccion
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexBob

# MINAMOS 1 BLOQUE PARA QUE LA TRANSACCION SE CONFIRME
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$AddressMiner"

# Visualizamos el balance final de la wallet miner
balance=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
#echo "Balance del Miner: $balance"

# Visualizamos el balance final de la wallet Alice
balance=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" getbalance)
#echo "Balance de Alice: $balance"

# Visualizamos el balance final de la wallet Bob
balance=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" getbalance)
#echo "Balance de Bob: $balance"

# Extraer los descriptores de las wallets Alice y Bob
echo "Extrayendo descriptores de las wallets Alice y Bob ..."
descAint=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
descAext=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
#printf "descAint: %s\n" "$descAint"
#printf "descAext: %s\n" "$descAext"

descBint=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
descBext=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("pkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
#printf "descBint: %s\n" "$descBint"
#printf "descBext: %s\n" "$descBext"

# Crea una wallet multi-sig con los descriptors
# importa los descriptores 
echo "Creando descriptors para la wallet multi-sig ..."
extdesc="wsh(multi(2,$descAext,$descBext))"
intdesc="wsh(multi(2,$descAint,$descBint))"
#echo "extdesc: $extdesc"
#echo "intdesc: $intdesc"

# Crea la wallet multi-sig en blanco 
echo "Creando wallet multi-sig en blanco ..."
$bitcoinCli -conf="$BitConf_ABS" -regtest -named createwallet wallet_name="multi" disable_private_keys=true blank=true

# Genera los checksum para la wallet multi-sig
echo "Generando checksum para la wallet multi-sig ..."
extdescsum=$($bitcoinCli -conf="$BitConf_ABS" -regtest getdescriptorinfo "$extdesc" | jq -r '.descriptor')
intdescsum=$($bitcoinCli -conf="$BitConf_ABS" -regtest getdescriptorinfo "$intdesc" | jq -r '.descriptor')
#echo "extdescsum: $extdescsum"
#echo "intdescsum: $intdescsum"

# Prepara los datos para importar los descriptores y se cargan en la wallet multi-sig
echo "Preparando datos para importar descriptores ..."
json_data=$(jq -n \
  --arg ext "$extdescsum" \
  --arg int "$intdescsum" \
  '[
    {desc: $ext, timestamp: "now", active: true, "watching-only": true, internal: false, range: [0,999]},
    {desc: $int, timestamp: "now", active: true, "watching-only": true, internal: true, range: [0,999]}
  ]')

import_result=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="multi" importdescriptors "$json_data")
#echo "Import result: $import_result"

# Consulta la informacion de la wallet multi-sig
echo "Consultando informacion de la wallet multi-sig ..."
info=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="multi" getwalletinfo)
#echo "Info de multi: $info"

# Genera un direccion de recepcion
echo "Generando direccion de recepcion multi"
multi_sig_addr=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="multi" getnewaddress)
#echo "Direccion de recepcion multi: $multi_sig_addr"


# Consultamos UTXOs de Alice y Bob
# Captura de las informacion de los txid y vout necesarios
echo "Capturando UTXOs de Alice y Bob ..."
utxo_txid_A=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" listunspent | jq -r '.[0] | .txid')
utxo_vout_A=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" listunspent | jq -r '.[0] | .vout')
utxo_txid_B=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" listunspent | jq -r '.[0] | .txid')
utxo_vout_B=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" listunspent | jq -r '.[0] | .vout')

# Visualizacion de la informacion capturada
echo $utxo_txid_A
echo $utxo_vout_A
echo $utxo_txid_B
echo $utxo_vout_B

# Generamos direcciones de cambio para Alice y Bob
echo "Generando direcciones de cambio para Alice y Bob"
change_addr_Alice=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" getnewaddress)
change_addr_Bob=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" getnewaddress)


# Creacion de la transaccion parcialmente firmada psbt
echo "Creacion de la transaccion parcialmente firmada psbt"
psbt=$($bitcoinCli -conf="$BitConf_ABS" -regtest createpsbt \
  "[{\"txid\":\"$utxo_txid_A\",\"vout\":$utxo_vout_A}, {\"txid\":\"$utxo_txid_B\",\"vout\":$utxo_vout_B}]" \
  "{\"$multi_sig_addr\": 20, \"$change_addr_Alice\": 9.99998, \"$change_addr_Bob\": 9.99998}")
#echo "PSBT: $psbt"


# Firmando los PSBTs
echo "Firma del PSBT por parte de Alice"
psbtA_signed=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" walletprocesspsbt "$psbt" | jq -r '.psbt')
#echo "PSBT_Alice_signed: $psbtA_signed"
echo "Firma del PSBT por parte de Bob"
psbtB_signed=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" walletprocesspsbt "$psbt" | jq -r '.psbt')
#echo "PSBT_Bob_signed: $psbtB_signed"

echo "Combinando los PSBTs..."
# Combinando los PSBTs
psbt_combined=$($bitcoinCli -conf="$BitConf_ABS" -regtest combinepsbt "[\"$psbtA_signed\",\"$psbtB_signed\"]" )
#echo "PSBT_combined: $psbt_combined"

# Finalizando el PSBT capturamos el hex para transmitir la transaccion
echo "Finalizando el PSBT..."
psbt_hex=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named finalizepsbt psbt="$psbt_combined" | jq -r '.hex')
#echo "PSBT_final: $psbt_hex"

# Transmitimos la transaccion
echo "Transmitiendo la transaccion..."
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$psbt_hex

# MINAMOS 1 BLOQUE PARA QUE LA TRANSACCION SE CONFIRME
echo "Minando 1 bloque..."
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$AddressMiner"

# Consulta el balance de la wallet multi-sig
echo "Consultando el balance de la wallet multi-sig..."
utxo_multi=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="multi" listunspent)
echo "UTXO de multi: $utxo_multi"


echo "Consultando el balance de la wallet Alice..."
$bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Alice" listunspent

echo "Consultando el balance de la wallet Bob..."
$bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Bob" listunspent