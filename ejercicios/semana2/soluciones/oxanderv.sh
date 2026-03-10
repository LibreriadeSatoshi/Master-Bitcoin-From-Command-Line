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

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Trader" 2>/dev/null; then
    echo "Wallet 'Trader' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Trader"
else
    echo "Wallet 'Trader' creada exitosamente"
fi


# Creando direccion para minero pero con la funcion getrawchangeaddress
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

# Genera una direccion de destino para Trader wallet
destinationaddressTrader=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Trader" -named getnewaddress label="Destino")
echo "Direccion de destino: $destinationaddressTrader"

# Crear la transaccion PARENT activando RBF
rawtxhex=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": 1 }, { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressTrader'": 70, "'$changeaddressMiner'": 29.99999 }''')

# Decodificamos la transaccion para ver como quedo construida
decRaw_transac=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named decoderawtransaction hexstring=$rawtxhex)
echo "Transaccion decodificada: $decRaw_transac"

# Firmamos la transaccion
signedtxhex=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhex | jq -r '.hex')

echo "Transaccion firmada: $signedtxhex"

# Transmitimos la transaccion
transactionid=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhex)
echo "Transaccion transmitida: $transactionid"

# Verificamos la transaccion
echo "Verificamos la transaccion transmitida:"
transactioninfo=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named gettransaction txid=$transactionid verbose=true)
echo "$transactioninfo"
# Extraccion de la informacion de las variables necesarias
miner_txid1=$(echo "$transactioninfo" | jq -r '.decoded.vin[0].txid')
vout1=$(echo "$transactioninfo" | jq -r '.decoded.vin[0].vout')
miner_txid2=$(echo "$transactioninfo" | jq -r '.decoded.vin[1].txid')
vout2=$(echo "$transactioninfo" | jq -r '.decoded.vin[1].vout')

miner_script=$(echo "$transactioninfo" | jq -r '.decoded.vout[1].scriptPubKey.hex')
miner_amount=$(echo "$transactioninfo" | jq -r '.decoded.vout[1].value')
trader_script=$(echo "$transactioninfo" | jq -r '.decoded.vout[0].scriptPubKey.hex')
trader_amount=$(echo "$transactioninfo" | jq -r '.decoded.vout[0].value')

# Calcular el fee de la transaccion
amount1=$(echo "$listUtxo" | jq -r --arg txid "$miner_txid1" '.[] | select(.txid == $txid) | .amount')
amount2=$(echo "$listUtxo" | jq -r --arg txid "$miner_txid2" '.[] | select(.txid == $txid) | .amount')
total_in=$(echo "$amount1 + $amount2" | bc -l)
total_out=$(echo "$miner_amount + $trader_amount" | bc -l)
fees=$(echo "scale=8; $total_in - $total_out" | bc -l)

# Extraer el weight de la transaccion
weight=$(echo "$decRaw_transac" | jq -r '.weight')

# Crea la variable JSON
tx_json=$(jq -n \
  --arg txid1 "$miner_txid1" --argjson vout1 "$vout1" \
  --arg txid2 "$miner_txid2" --argjson vout2 "$vout2" \
  --arg mscript "$miner_script" --argjson mamount "$miner_amount" \
  --arg tscript "$trader_script" --argjson tamount "$trader_amount" \
  --argjson fees "$fees" --argjson weight "$weight" '
{
  "input": [
    { "txid": $txid1, "vout": $vout1 },
    { "txid": $txid2, "vout": $vout2 }
  ],
  "output": [
    { "script_pubkey": $mscript, "amount": $mamount },
    { "script_pubkey": $tscript, "amount": $tamount }
  ],
  "Fees": $fees,
  "Weight": $weight
}
')

# Imprimir el JSON
echo "Imprimiendo el JSON"
echo "$tx_json"

# Creando la transaccion CHILD
# Obtenemos la transaccion del mempool
rawmempool=$($bitcoinCli -conf="$BitConf_ABS" -regtest getrawmempool)
echo "Mempool Primera consulta:"
echo $rawmempool

# Decodificamos la transaccion encontrada en la mempool, como es la unica, tomamos el primer elemento
# En escenarios reales debemos buscar la transaccion entre muchas otras ¡Precaución!
rawtxjson=$($bitcoinCli -conf="$BitConf_ABS" -regtest getrawtransaction $transactionid 1)

# Se extraen los datos de la transaccion padre, address del cambio y n
parent_txid=$(echo "$rawtxjson" | jq -r '.txid')
parent_n=$(echo "$rawtxjson" | jq -r '.vout[1].n')

# Generando una segunda direccion para recibir el resto de los fondos CHILD
addressChild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getnewaddress label="Transaccion Child")

# Crear la transaccion CHILD
rawtxhexchild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$parent_txid'", "vout": '$parent_n' } ]''' outputs='''{ "'$addressChild'": 29.99998 }''')

# Firmamos la transaccion CHILD
signedtxhexchild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhexchild | jq -r '.hex')

# Transmitimos la transaccion CHILD
transactionidchild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexchild)

# Verificamos la transaccion CHILD en el mempool
transactioninfoChild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getmempoolentry txid=$transactionidchild)
echo "Child transaction info antes de modificar transaccion PARENT:"
echo "$transactioninfoChild"

# Aumentamos la tarifa de la transaccion PARENT usando los mismos datos de la primera transaccion PARENT
rawtxhex=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": 1 }, { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressTrader'": 70, "'$changeaddressMiner'": 29.9999 }''')
# Firmamos la transaccion PARENT 2
signedtxhex2=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhex | jq -r '.hex')
# Transmitimos la transaccion PARENT 2
transactionid2=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhex2)
# Verificamos la transaccion CHILD en el mempool
echo "Child transaction info despues de modificar transaccion PARENT:"
transactioninfoChild=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getmempoolentry txid=$transactionidchild)
echo "$transactioninfoChild"

# Obtenemos la transaccion del mempool
rawmempool=$($bitcoinCli -conf="$BitConf_ABS" -regtest getrawmempool)
echo "Mempool Segunda consulta:"
echo $rawmempool

# Finalizamos apagando el nodo de bitcoin
$bitcoinCli -conf="$BitConf_ABS" stop
sleep 5
echo "Proceso detenido, Nodo de Bitcoin apagado"


# EXPLICACION DEL RESULTADO

# El resultado muestra que la transaccion child ocupo un espacio en la mempool cuando usaba la transaccion parent
# como entrada y ofrecía 0.00002 BTC de comision, tambien mostró una disminucion en weight con 437 bytes, 
# despues de modificar la transaccion parent aumentando su tarifa en 0.0001 BTC, la transaccion child se vio afectada
# al momento de consultarla con el comando getmempoolentry usando la misma txid el nodo responde con "Transaction not in mempool"
# ha sido eliminada y reemplazada por la nueva transaccion parent modificada, esto ocurrio debido a que los mineros prefieren 
# procesar transacciones con mejor tarifa, y esta entró en conflicto con la primera transaccion parent 
# y a su vez con la transaccion child, debido a que usaban los mismos UTXOs y fueron eliminadas de la mempool.
