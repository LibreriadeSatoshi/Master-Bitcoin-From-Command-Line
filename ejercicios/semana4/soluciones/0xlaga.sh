#!/bin/bash
# Autor: 0xlaga
# Semana 4 - Timelocks, OP_RETURN y Relative Timelocks en regtest

set -e

BCLI="bitcoin-cli -regtest"

###############################################################################
# PARTE 1 – CONFIGURAR CONTRATO TIMELOCK
###############################################################################

# 1. Crear wallets: Miner, Empleado, Empleador
echo "=== 1. Creando wallets ==="
for W in Miner Empleado Empleador; do
  $BCLI createwallet "$W" 2>/dev/null || $BCLI loadwallet "$W" 2>/dev/null || true
done

# 2. Fondear wallets
echo "=== 2. Fondeando wallets ==="
MINER_ADDR=$($BCLI -rpcwallet=Miner getnewaddress "Recompensa")
$BCLI generatetoaddress 103 "$MINER_ADDR" > /dev/null

EMPLEADOR_ADDR=$($BCLI -rpcwallet=Empleador getnewaddress "Fondeo")
$BCLI -rpcwallet=Miner sendtoaddress "$EMPLEADOR_ADDR" 50 > /dev/null
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "Empleador: $($BCLI -rpcwallet=Empleador getbalance) BTC"

# 3. Crear tx de salario de 40 BTC con timelock absoluto de 500 bloques
echo "=== 3. Creando tx de salario con timelock absoluto (bloque 500) ==="

EMPLEADO_ADDR=$($BCLI -rpcwallet=Empleado getnewaddress "Salario")
EMPLEADOR_CHANGE=$($BCLI -rpcwallet=Empleador getrawchangeaddress)

UTXO=$($BCLI -rpcwallet=Empleador listunspent | jq '.[0]')
TXID=$(echo "$UTXO" | jq -r '.txid')
VOUT=$(echo "$UTXO" | jq '.vout')
AMT=$(echo "$UTXO" | jq '.amount')

CHANGE=$(echo "$AMT - 40 - 0.0001" | bc -l)

# 4. Locktime = 500 bloques
SALARY_RAW=$($BCLI createrawtransaction \
  "[{\"txid\":\"$TXID\",\"vout\":$VOUT,\"sequence\":4294967294}]" \
  "[{\"$EMPLEADO_ADDR\":40},{\"$EMPLEADOR_CHANGE\":$CHANGE}]" \
  500)

SALARY_SIGNED=$($BCLI -rpcwallet=Empleador signrawtransactionwithwallet "$SALARY_RAW" | jq -r '.hex')

# 5. Intentar transmitir antes del bloque 500
echo "=== 5. Intentando transmitir antes del bloque 500 ==="
CURRENT_BLOCK=$($BCLI getblockcount)
echo "Bloque actual: $CURRENT_BLOCK"

# La tx tiene locktime=500, por lo que no se puede incluir hasta que se mine el bloque 500.
# bitcoin-cli rechazará con: "non-final" 
$BCLI sendrawtransaction "$SALARY_SIGNED" 2>&1 || true
echo "# COMENTARIO: La tx es rechazada con error 'non-final' porque el locktime (500)"
echo "# aún no se ha alcanzado. La tx no puede incluirse en un bloque hasta el bloque 500."

# 6. Minar hasta el bloque 500 y transmitir
echo "=== 6. Minando hasta bloque 500 ==="
BLOCKS_NEEDED=$((500 - $($BCLI getblockcount)))
if [ "$BLOCKS_NEEDED" -gt 0 ]; then
  $BCLI generatetoaddress "$BLOCKS_NEEDED" "$MINER_ADDR" > /dev/null
fi
echo "Bloque actual: $($BCLI getblockcount)"

SALARY_TXID=$($BCLI sendrawtransaction "$SALARY_SIGNED")
echo "Tx de salario transmitida: $SALARY_TXID"

$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# 7. Saldos
echo "=== 7. Saldos después del timelock ==="
echo "Empleado:  $($BCLI -rpcwallet=Empleado getbalance) BTC"
echo "Empleador: $($BCLI -rpcwallet=Empleador getbalance) BTC"

###############################################################################
# PARTE 2 – GASTAR DESDE EL TIMELOCK CON OP_RETURN
###############################################################################

echo ""
echo "============================================="
echo "    GASTAR DESDE EL TIMELOCK + OP_RETURN"
echo "============================================="

# 1. Crear tx de gasto del Empleado a nueva dirección propia
echo "=== 1. Creando tx de gasto con OP_RETURN ==="

EMPLEADO_NEW_ADDR=$($BCLI -rpcwallet=Empleado getnewaddress "Celebracion")

EMP_UTXO=$($BCLI -rpcwallet=Empleado listunspent | jq '.[0]')
EMP_TXID=$(echo "$EMP_UTXO" | jq -r '.txid')
EMP_VOUT=$(echo "$EMP_UTXO" | jq '.vout')
EMP_AMT=$(echo "$EMP_UTXO" | jq '.amount')

EMP_SEND=$(echo "$EMP_AMT - 0.0001" | bc -l)

# 2. Convertir el mensaje a hex para OP_RETURN
OP_RETURN_MSG="He recibido mi salario, ahora soy rico"
OP_RETURN_HEX=$(echo -n "$OP_RETURN_MSG" | xxd -p | tr -d '\n')

SPEND_RAW=$($BCLI createrawtransaction \
  "[{\"txid\":\"$EMP_TXID\",\"vout\":$EMP_VOUT}]" \
  "[{\"$EMPLEADO_NEW_ADDR\":$EMP_SEND},{\"data\":\"$OP_RETURN_HEX\"}]")

# 3. Firmar y transmitir
SPEND_SIGNED=$($BCLI -rpcwallet=Empleado signrawtransactionwithwallet "$SPEND_RAW" | jq -r '.hex')
SPEND_TXID=$($BCLI sendrawtransaction "$SPEND_SIGNED")
echo "Tx de gasto con OP_RETURN: $SPEND_TXID"

$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# Verificar el OP_RETURN en la tx
echo "OP_RETURN en la tx:"
$BCLI getrawtransaction "$SPEND_TXID" true | jq '.vout[] | select(.scriptPubKey.type == "nulldata")'

# 4. Saldos finales
echo "=== 4. Saldos después del gasto ==="
echo "Empleado:  $($BCLI -rpcwallet=Empleado getbalance) BTC"
echo "Empleador: $($BCLI -rpcwallet=Empleador getbalance) BTC"

###############################################################################
# PARTE 3 – TIMELOCK RELATIVO
###############################################################################

echo ""
echo "============================================="
echo "       TIMELOCK RELATIVO (10 bloques)"
echo "============================================="

# 1. Crear tx donde Empleador paga 1 BTC a Miner con timelock relativo de 10 bloques
echo "=== 1. Creando tx con timelock relativo ==="

MINER_RECV=$($BCLI -rpcwallet=Miner getnewaddress "Desde_Empleador")
EMPLEADOR_CHANGE2=$($BCLI -rpcwallet=Empleador getrawchangeaddress)

UTXO2=$($BCLI -rpcwallet=Empleador listunspent | jq '.[0]')
TXID2=$(echo "$UTXO2" | jq -r '.txid')
VOUT2=$(echo "$UTXO2" | jq '.vout')
AMT2=$(echo "$UTXO2" | jq '.amount')

CHANGE2=$(echo "$AMT2 - 1 - 0.0001" | bc -l)

# sequence = 10 para timelock relativo de 10 bloques
RELATIVE_RAW=$($BCLI createrawtransaction \
  "[{\"txid\":\"$TXID2\",\"vout\":$VOUT2,\"sequence\":10}]" \
  "[{\"$MINER_RECV\":1},{\"$EMPLEADOR_CHANGE2\":$CHANGE2}]")

RELATIVE_SIGNED=$($BCLI -rpcwallet=Empleador signrawtransactionwithwallet "$RELATIVE_RAW" | jq -r '.hex')

# 2. Intentar transmitir inmediatamente
echo "=== 2. Intentando transmitir antes de 10 bloques ==="
$BCLI sendrawtransaction "$RELATIVE_SIGNED" 2>&1 || true
echo "# COMENTARIO: La tx es rechazada con error 'non-BIP68-final' porque el timelock"
echo "# relativo de 10 bloques no se ha cumplido desde la confirmación del UTXO referenciado."

###############################################################################
# PARTE 4 – GASTAR DESDE EL TIMELOCK RELATIVO
###############################################################################

echo ""
echo "============================================="
echo "   GASTAR DESDE EL TIMELOCK RELATIVO"
echo "============================================="

# 1. Generar 10 bloques adicionales
echo "=== 1. Minando 10 bloques ==="
$BCLI generatetoaddress 10 "$MINER_ADDR" > /dev/null
echo "Bloque actual: $($BCLI getblockcount)"

# 2. Transmitir y confirmar
echo "=== 2. Transmitiendo tx con timelock relativo ==="
REL_TXID=$($BCLI sendrawtransaction "$RELATIVE_SIGNED")
echo "Tx relativa transmitida: $REL_TXID"

$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# 3. Saldo final del Empleador
echo "=== 3. Saldo final ==="
echo "Empleador: $($BCLI -rpcwallet=Empleador getbalance) BTC"

echo ""
echo "✅ Ejercicio Semana 4 completado."
