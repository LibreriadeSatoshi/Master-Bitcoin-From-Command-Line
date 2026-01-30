#!/bin/bash
set -euo pipefail

DATA_DIR="$HOME/.bitcoin"
CONF_FILE="$DATA_DIR/bitcoin.conf"

# Configuración inicial de Bitcoin Core
echo "> Configurando entorno en $DATA_DIR..."
mkdir -p "$DATA_DIR"
cat > "$CONF_FILE" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=fabohax
rpcpassword=40230
rpcallowip=127.0.0.1
EOF

# Detener cualquier instancia previa de bitcoind
echo "> Reiniciando bitcoind si está activo..."
if pgrep -x "bitcoind" > /dev/null; then
  bitcoin-cli -regtest stop 2>/dev/null || pkill -x bitcoind
  sleep 3
fi

# Iniciar bitcoind en modo regtest
echo "> Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 3

# Definir BITCOIN_CLI después de que bitcoind esté corriendo
BITCOIN_CLI="bitcoin-cli -regtest -rpcuser=fabohax -rpcpassword=40230"

# Esperar a que bitcoind esté completamente listo
echo "> Esperando a que bitcoind esté listo..."
while ! $BITCOIN_CLI getblockchaininfo >/dev/null 2>&1; do
  sleep 1
done

# Limpiar wallets existentes para empezar desde cero
echo "> Borrando wallets existentes..."
rm -rf "$DATA_DIR/regtest/wallets"
mkdir -p "$DATA_DIR/regtest/wallets"

# === Crear wallets nuevas para el ejercicio ===
for WALLET in Miner Empleado Empleador; do
    echo "> Creando nueva wallet '$WALLET'..."
    $BITCOIN_CLI -named createwallet wallet_name=$WALLET descriptors=true load_on_startup=true
done

# Obtener dirección de minería (usar formato legacy para compatibilidad)
MINER_ADDR=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress "Miner" legacy)

# Verificar que las herramientas necesarias estén instaladas
echo "> Minando hasta obtener saldo positivo..."
blocks=0
balance=0
command -v bc >/dev/null 2>&1 || { echo >&2 "▓ Error: 'bc' no está instalado. Ejecuta: sudo apt install bc"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "▓ Error: 'jq' no está instalado. Ejecuta: sudo apt install jq"; exit 1; }

# Minar bloques iniciales hasta que las recompensas maduren (100+ bloques)
while [ "$balance" = "0.00000000" ]; do
  $BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
  sleep 0.2
  balance=$($BITCOIN_CLI -rpcwallet=Miner getbalance || echo 0)
  ((blocks++))
done

echo "> $blocks bloques minados. Saldo Miner: $balance BTC"

# Minar bloques adicionales hasta tener suficiente saldo maduro
TARGET_BALANCE=150
echo "> Minando hasta que Miner tenga al menos $TARGET_BALANCE BTC disponibles..."
while true; do
    SALDO=$($BITCOIN_CLI -rpcwallet=Miner getbalance "*" 1)
    echo "  > Saldo actual: $SALDO BTC"
    
    if (( $(echo "$SALDO >= $TARGET_BALANCE" | bc -l) )); then
        break
    fi
    
    $BITCOIN_CLI generatetoaddress 10 "$MINER_ADDR" > /dev/null
    sleep 1  # Dar tiempo al nodo para procesar los nuevos bloques
done

echo "> Saldo final de Miner: $SALDO BTC"

# === Enviar fondos iniciales al Empleador ===
echo "> Enviando 50 BTC al Empleador..."
ADDR_EMPLEADOR=$($BITCOIN_CLI -rpcwallet=Empleador getnewaddress)
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$ADDR_EMPLEADOR" 50
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR"

echo "> Saldos actuales:"
echo "Empleador: $($BITCOIN_CLI -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $($BITCOIN_CLI -rpcwallet=Empleado getbalance) BTC"

# === Crear transacción con timelock absoluto ===
echo "> Creando transacción de salario con timelock de 500 bloques..."

# Obtener bloque actual para calcular timelock apropiado
CURRENT_BLOCK=$($BITCOIN_CLI getblockcount)
TIMELOCK_BLOCK=$((CURRENT_BLOCK + 50))  # Timelock relativo de 50 bloques adelante
echo "> Bloque actual: $CURRENT_BLOCK, timelock establecido para bloque: $TIMELOCK_BLOCK"

# Obtener dirección del empleado para recibir el salario
ADDR_EMPLEADO=$($BITCOIN_CLI -rpcwallet=Empleado getnewaddress)

# Obtener UTXO del empleador para financiar la transacción
UTXO_EMPLEADOR=$($BITCOIN_CLI -rpcwallet=Empleador listunspent | jq -r '.[0]')
TXID_EMPLEADOR=$(echo "$UTXO_EMPLEADOR" | jq -r .txid)
VOUT_EMPLEADOR=$(echo "$UTXO_EMPLEADOR" | jq -r .vout)
AMOUNT_EMPLEADOR=$(echo "$UTXO_EMPLEADOR" | jq -r .amount)

# Calcular el cambio que regresa al empleador
SALARY_AMOUNT=40
FEE_AMOUNT=0.001  # Agregar fee explícito
CHANGE_EMPLEADOR=$(echo "$AMOUNT_EMPLEADOR - $SALARY_AMOUNT - $FEE_AMOUNT" | bc)

# Crear transacción raw con timelock
echo "> Creando transacción raw con locktime=$TIMELOCK_BLOCK..."
RAW_TX=$($BITCOIN_CLI createrawtransaction "[{\"txid\":\"$TXID_EMPLEADOR\",\"vout\":$VOUT_EMPLEADOR}]" "{\"$ADDR_EMPLEADO\":$SALARY_AMOUNT,\"$ADDR_EMPLEADOR\":$CHANGE_EMPLEADOR}" $TIMELOCK_BLOCK)

# Firmar la transacción con la wallet del empleador
echo "> Firmando transacción..."
SIGNED_TX=$($BITCOIN_CLI -rpcwallet=Empleador signrawtransactionwithwallet "$RAW_TX")
COMPLETE_TX=$(echo "$SIGNED_TX" | jq -r .hex)

# Minar hasta llegar al bloque timelock
echo "> Minando hasta el bloque $TIMELOCK_BLOCK..."
while [ $($BITCOIN_CLI getblockcount) -lt $TIMELOCK_BLOCK ]; do
    CURRENT_BLOCK=$($BITCOIN_CLI getblockcount)
    REMAINING_BLOCKS=$((TIMELOCK_BLOCK - CURRENT_BLOCK))
    
    # Minar en lotes para mejorar eficiencia
    if [ $REMAINING_BLOCKS -gt 20 ]; then
        $BITCOIN_CLI generatetoaddress 20 "$MINER_ADDR" > /dev/null
    elif [ $REMAINING_BLOCKS -gt 5 ]; then
        $BITCOIN_CLI generatetoaddress 5 "$MINER_ADDR" > /dev/null
    else
        $BITCOIN_CLI generatetoaddress $REMAINING_BLOCKS "$MINER_ADDR" > /dev/null
    fi
    
    CURRENT_BLOCK=$($BITCOIN_CLI getblockcount)
    echo "  > Bloque actual: $CURRENT_BLOCK (faltan $((TIMELOCK_BLOCK - CURRENT_BLOCK)) bloques)"
done

# Ahora la transacción debería ser aceptada
echo "> Se alcanzó el bloque $TIMELOCK_BLOCK. Transmitiendo transacción de salario..."
TXID_SALARY=$($BITCOIN_CLI sendrawtransaction "$COMPLETE_TX")
echo "> Transacción de salario transmitida: $TXID_SALARY"

# Minar un bloque adicional para confirmar la transacción
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "> Saldos después del pago de salario:"
echo "Empleador: $($BITCOIN_CLI -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $($BITCOIN_CLI -rpcwallet=Empleado getbalance) BTC"

# === Gastar desde el Empleado con OP_RETURN ===
echo "> Creando transacción de gasto con OP_RETURN..."

# Obtener nueva dirección del empleado para el gasto
ADDR_EMPLEADO_NEW=$($BITCOIN_CLI -rpcwallet=Empleado getnewaddress)

# Obtener UTXO del empleado (el salario recibido)
UTXO_EMPLEADO=$($BITCOIN_CLI -rpcwallet=Empleado listunspent | jq -r '.[0]')
TXID_EMPLEADO=$(echo "$UTXO_EMPLEADO" | jq -r .txid)
VOUT_EMPLEADO=$(echo "$UTXO_EMPLEADO" | jq -r .vout)
AMOUNT_EMPLEADO=$(echo "$UTXO_EMPLEADO" | jq -r .amount)

# Calcular cantidad después de fees
FEE_AMOUNT_SPEND=0.001  # Fee para la transacción de gasto
SPEND_AMOUNT=$(echo "$AMOUNT_EMPLEADO - $FEE_AMOUNT_SPEND" | bc)  # Usar todo menos fee
OP_RETURN_DATA="He recibido mi salario, ahora soy rico (!)"
# Convertir el mensaje a hexadecimal para OP_RETURN
OP_RETURN_HEX=$(echo -n "$OP_RETURN_DATA" | xxd -p | tr -d '\n')

# Crear transacción con salida OP_RETURN
echo "> Creando transacción con OP_RETURN: '$OP_RETURN_DATA'"
RAW_TX_SPEND=$($BITCOIN_CLI createrawtransaction "[{\"txid\":\"$TXID_EMPLEADO\",\"vout\":$VOUT_EMPLEADO}]" "{\"$ADDR_EMPLEADO_NEW\":$SPEND_AMOUNT,\"data\":\"$OP_RETURN_HEX\"}")

# Firmar y transmitir la transacción de gasto
SIGNED_TX_SPEND=$($BITCOIN_CLI -rpcwallet=Empleado signrawtransactionwithwallet "$RAW_TX_SPEND")
COMPLETE_TX_SPEND=$(echo "$SIGNED_TX_SPEND" | jq -r .hex)

echo "> Transmitiendo transacción de gasto con OP_RETURN..."
TXID_SPEND=$($BITCOIN_CLI sendrawtransaction "$COMPLETE_TX_SPEND")
echo "> Transacción de gasto transmitida: $TXID_SPEND"

# Minar para confirmar la transacción de gasto
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# === Mostrar saldos finales ===
echo "> ▓ Saldos finales:"
echo "Empleador: $($BITCOIN_CLI -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $($BITCOIN_CLI -rpcwallet=Empleado getbalance) BTC"

# Verificar y mostrar los datos OP_RETURN
echo "> Verificando datos OP_RETURN en la transacción..."
TX_INFO=$($BITCOIN_CLI getrawtransaction "$TXID_SPEND" true)
OP_RETURN_OUTPUT=$(echo "$TX_INFO" | jq -r '.vout[] | select(.scriptPubKey.type == "nulldata") | .scriptPubKey.hex')
if [ "$OP_RETURN_OUTPUT" != "null" ]; then
    # Extraer datos después del opcode OP_RETURN (6a es OP_RETURN, siguiente byte es longitud)
    DATA_HEX=$(echo "$OP_RETURN_OUTPUT" | sed 's/^6a..//')
    DATA_DECODED=$(echo "$DATA_HEX" | xxd -r -p)
    echo "> Datos OP_RETURN encontrados: '$DATA_DECODED'"
else
    echo "> No se encontraron datos OP_RETURN en la transacción"
fi

echo "▓ Script completo ejecutado con éxito."
echo "   - Se creó una transacción con timelock absoluto de $TIMELOCK_BLOCK bloques"
echo "   - Se minó hasta el bloque $TIMELOCK_BLOCK para poder transmitir la transacción"
echo "   - Se gastaron los fondos con una salida OP_RETURN conteniendo el mensaje de celebración"
