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

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Empresario" 2>/dev/null; then
    echo "Wallet 'Empresario' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Empresario"
else
    echo "Wallet 'Empresario' creada exitosamente"
fi

if ! $bitcoinCli -conf="$BitConf_ABS" createwallet "Empleado" 2>/dev/null; then
    echo "Wallet 'Empleado' ya existe, cargando..."
    $bitcoinCli -conf="$BitConf_ABS" loadwallet "Empleado"
else
    echo "Wallet 'Empleado' creada exitosamente"
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
    
    if (( $(echo "$balance >= 200" | bc -l) )); then
        echo "¡Balance >= 200 ($balance)! Saliendo del bucle."
        break
    else
        echo "Balance < 200. Minando 1 bloque por vez..."
        $bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress)"
        echo "Bloques minados. Esperando confirmaciones..."
        sleep 2  # Pequeña pausa para que se procesen las confirmaciones
    fi
done

# Visualizacion de los UTXO existentes para Miner wallet
listUtxo=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent)

# Captura de las informacion de los txid y vout necesarios 
utxo_txid_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .txid')
utxo_vout_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .vout')

# Visualizacion de la informacion capturada
echo $utxo_txid_0
echo $utxo_vout_0

# Genera una direccion de cambio para Miner wallet
changeaddressMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getnewaddress label="Cambio")
echo "Direccion de cambio: $changeaddressMiner"

# Genera una direccion de destino para Empresario wallet
destinationaddressEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" -named getnewaddress label="Destino")
echo "Direccion de destino Empresario: $destinationaddressEmpresario"


# CREAR, FIRMAR Y TRANSMITIR TRANSACCIONES PARA FONDEAR WALLET EMPRESARIO
# Crear la transaccion para fondear wallet Empresario
rawtxhexEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressEmpresario'": 49, "'$changeaddressMiner'": 0.99998 }''')
# Firmamos la transaccion Empresario
signedtxhexEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named signrawtransactionwithwallet hexstring=$rawtxhexEmpresario | jq -r '.hex')
# Transmitimos la transaccion
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexEmpresario
echo "Fondos enviados a la wallet empresario"
# MINAMOS 1 BLOQUE PARA QUE LA TRANSACCION SE CONFIRME
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$AddressMiner"

# CREAMOS LA TRANSACCION PARA EL PAGO DEL SALARIO DEL EMPLEADO
# Captura de las informacion de los txid y vout necesarios de la wallet del empresario
utxo_txid_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" listunspent | jq -r '.[0] | .txid')
utxo_vout_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" listunspent | jq -r '.[0] | .vout')
# Visualizacion de la informacion capturada
echo $utxo_txid_0
echo $utxo_vout_0

# Configuramos la variable para condicionar el pago segun la altura del bloque
bloquesDeMas=$((500 - $($bitcoinCli -conf="$BitConf_ABS" -regtest getblockcount)))
echo "Bloques faltantes: $bloquesDeMas"

# Genera una direccion de cambio para Empresario wallet
changeaddressEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" -named getnewaddress label="Cambio")
echo "Direccion de cambio: $changeaddressEmpresario"

# Genera una direccion de destino para Empleado wallet
destinationaddressEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" -named getnewaddress label="Destino")
echo "Direccion de destino Empleado: $destinationaddressEmpleado"

# Crear la transaccion para fondear wallet Empleado
rawtxhexEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": 1 } ]''' outputs='''{ "'$destinationaddressEmpleado'": 20, "'$changeaddressEmpresario'": 28.99998 }''' locktime=$bloquesDeMas)
echo "Transaccion creada"
# Firmamos la transaccion Empresario
signedtxhexEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" -named signrawtransactionwithwallet hexstring=$rawtxhexEmpleado | jq -r '.hex')
echo "Transaccion firmada"
# Transmitimos la transaccion
echo "Transaccion transmitida"
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexEmpleado

echo "COMENTARIO"
echo "Se genera un error al tratar de transmitir la transaccion a la red debido a que la blockchain"
echo "aun no ha alcanzado la altura de bloque necesaria"
sleep 10

# Creamos un bucle para minar hasta alcanzar la altura de bloque deseada
altura_actual=$($bitcoinCli -conf="$BitConf_ABS" -regtest getblockcount)
altura_objetivo=501

for ((altura=$altura_actual; altura <= $altura_objetivo; altura++)); do
  echo "Generando bloque $altura..."
  # Minamos 1 bloque para buscar la altura deseada
  $bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress)"
done
altura_actual=$($bitcoinCli -conf="$BitConf_ABS" -regtest getblockcount)
echo "Llegamos a altura $altura_actual"

# Transmitimos de nuevo la transaccion para hacer el pago al empleado
echo "Transaccion transmitida"
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexEmpleado

# Minamos 1 bloque para confirmar la transaccion
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress)"
echo "Transaccion confirmada"

# Consultamos el balance de la wallet Empresario y del Empleado
balanceEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" getbalance)
echo "Balance Empresario: $balanceEmpresario"o
balanceEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" getbalance)
echo "Balance Empleado: $balanceEmpleado"

# Gastar desde el TimeLock
echo "Gastar desde el TimeLock"
# Genera una direccion de destino para Empleado wallet
destinationaddressEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" -named getnewaddress label="OP_RETURN_TRANSACTION")
echo "Direccion de destino Empleado: $destinationaddressEmpleado"

data="Estoy embilletado, ahora soy rico !!!"
echo "Data a incluir en OP_RETURN: $data"
# Convierte el texto en hexadecimal para incluirlo en la transaccion
op_return_data=$(echo $data | xxd -p | tr -d '\n')
echo "Data en hexadecimal: $op_return_data"

# Captura de las informacion de los txid y vout necesarios de la wallet del Empleado
utxo_txid_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" listunspent | jq -r '.[0] | .txid')
utxo_vout_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" listunspent | jq -r '.[0] | .vout')
# Visualizacion de la informacion capturada
echo $utxo_txid_0
echo $utxo_vout_0

# Creamos la transaccion
rawtxhexEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0' } ]''' outputs='''[{ "'$destinationaddressEmpleado'": 19.99999 },{ "data": "'$op_return_data'"}]''')

# Firmamos la transaccion Empleado
signedtxhexEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" -named signrawtransactionwithwallet hexstring=$rawtxhexEmpleado | jq -r '.hex')
echo "Transaccion firmada"

# Transmitimos la transaccion
echo "Transaccion transmitida"
txid=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexEmpleado)

# Minamos 1 bloque para confirmar la transaccion
echo "Transaccion confirmada"
$bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress)"

# Verificamos que la informacion quedó almacenada en la blockchain
echo "Verificando que la informacion quedó almacenada en la blockchain"
$bitcoinCli -conf="$BitConf_ABS" -regtest getrawtransaction $txid true
# Capturamos el HEX
op_return_asm_hex=$($bitcoinCli -conf="$BitConf_ABS" -regtest getrawtransaction "$txid" true | jq -r '.vout[] | select(.scriptPubKey.asm | startswith("OP_RETURN")) | .scriptPubKey.asm | split(" ")[1]')

echo "Hex desde ASM: $op_return_asm_hex"
echo "HEX Decodificado: $(echo "$op_return_asm_hex" | xxd -r -p)"

# Consultamos el balance de la wallet Empresario y del Empleado
balanceEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" getbalance)
echo "Balance Empresario: $balanceEmpresario"
balanceEmpleado=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empleado" getbalance)
echo "Balance Empleado: $balanceEmpleado"
balanceMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
echo "Balance Minero: $balanceMiner"


# Creacion de la transaccion con locktime relativo
# Captura de las informacion de los txid y vout necesarios 
utxo_txid_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" listunspent | jq -r '.[0] | .txid')
utxo_vout_0=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" listunspent | jq -r '.[0] | .vout')

# Visualizacion de la informacion capturada
echo "UTXO TXID: $utxo_txid_0"
echo "UTXO VOUT: $utxo_vout_0"

# Genera una direccion de cambio para Empresario wallet
changeaddressEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" -named getnewaddress label="Cambio")
echo "Direccion de cambio: $changeaddressEmpresario"

# Genera una direccion de destino para Miner wallet
destinationaddressMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" -named getnewaddress label="Destino")
echo "Direccion de destino Miner: $destinationaddressMiner"

# cantidad de bloques para el locktime relativo
# Se multiplica el numero de bloque por 4096 debido al estandar BIP-68
bloques=10
BIT31=2147483648
sequence=$((BIT31 + (bloques * 4096)))

# Crear la transaccion para pagar 1 btc al Minero
rawtxhexMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_0'", "vout": '$utxo_vout_0', "sequence": '$sequence' } ]''' outputs='''{ "'$destinationaddressMiner'": 1, "'$changeaddressEmpresario'": 27.99996000 }''')
echo "Transaccion Empresario -> Minero"
# Firmamos la transaccion pago al Minero
signedtxhexMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" -named signrawtransactionwithwallet hexstring=$rawtxhexMiner | jq -r '.hex')
echo "Transaccion firmada"
# Transmitimos la transaccion
echo "Transmitiendo la transaccion a la red regtest..."
$bitcoinCli -conf="$BitConf_ABS" -regtest -named sendrawtransaction hexstring=$signedtxhexMiner

echo "Balance Empresario al transmitir por primera vez la transaccion con locktime relativo"
balanceEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" getbalance)
echo "Balance Empresario: $balanceEmpresario"

balanceMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
echo "Balance Minero: $balanceMiner"

# Comentarios
echo "La red detecta que la transaccion emitida tiene un locktime relativo y muestra"
echo "el error: 'non-BIP68-final' "
echo "Los fondos son enviados a las direcciones de destino y cambio respectivamente"
echo "El balance del Empresario se reduce en 1 + el fee de la transaccion"
echo "El balance del minero no cambia, hasta que se mine el siguiente bloque"
sleep 10

# Minando los siguientes 10 bloques para poder procesar la transaccion
# Creamos un bucle para minar hasta alcanzar la altura de bloque deseada
altura_actual=$($bitcoinCli -conf="$BitConf_ABS" -regtest getblockcount)
altura_objetivo=$(($altura_actual + $bloques))
echo "Altura bloque actual: '$altura_actual"
sleep 3
for ((altura=$altura_actual; altura <= $altura_objetivo; altura++)); do
  echo "Generando bloque $altura..."
  # Minamos 1 bloque para buscar la altura deseada
  $bitcoinCli -conf="$BitConf_ABS" -regtest generatetoaddress 1 "$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getnewaddress)"

done
altura_actual=$($bitcoinCli -conf="$BitConf_ABS" -regtest getblockcount)
echo "Llegamos a altura $altura_actual"

echo "Balance Empresario despues de transmitir y minar la transaccion"
balanceEmpresario=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Empresario" getbalance)
echo "Balance Empresario: $balanceEmpresario"

echo "Balance minero despues de transmitir y minar la transaccion"
balanceMiner=$($bitcoinCli -conf="$BitConf_ABS" -regtest -rpcwallet="Miner" getbalance)
echo "Balance Minero: $balanceMiner"
echo "  "
echo "COMENTARIOS"
echo "Con una recompensa de 12.5 bitcoin por bloque y despues de 11 bloques minados"
echo "El minero recibe 137.5 bitcoin nuevos a sus fondos"
echo "Si le agregamos a los 12463.5 bitcoins previos la recompensa de los 11 ultimos bloque minados"
echo "Tenemos un total de 12601 bitcoin + 1 recibido del Empresario"
echo "Nos da un total de 12602 bitcoins"