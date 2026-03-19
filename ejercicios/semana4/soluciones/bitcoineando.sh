#!/usr/bin/env bash
# Ejercicio Semana 4 — Maestros de Bitcoin desde la línea de comandos
# Librería de Satoshi — MBFCL
#
# Simula un contrato salarial con timelocks y OP_RETURN:
#   1. Timelock absoluto: Empleador paga 40 BTC al Empleado, bloqueado hasta bloque 500
#   2. OP_RETURN: Empleado gasta y deja un mensaje en la blockchain
#   3. Timelock relativo: Empleador paga 1 BTC a Miner, bloqueado por 10 bloques

set -e

CLI="bitcoin-cli -regtest"

echo "============================================"
echo "  EJERCICIO SEMANA 4 — Timelocks y OP_RETURN"
echo "============================================"

# ============================================================
#  SETUP
# ============================================================

# --- 1. Crear wallets ---
echo ""
echo "--- 1. Creando wallets Miner, Empleado y Empleador ---"
$CLI createwallet "Miner"     > /dev/null 2>&1 || $CLI loadwallet "Miner"     > /dev/null 2>&1 || true
$CLI createwallet "Empleado"  > /dev/null 2>&1 || $CLI loadwallet "Empleado"  > /dev/null 2>&1 || true
$CLI createwallet "Empleador" > /dev/null 2>&1 || $CLI loadwallet "Empleador" > /dev/null 2>&1 || true
echo "Wallets: Miner, Empleado, Empleador"

# --- 2. Fondear wallets ---
echo ""
echo "--- 2. Fondeando wallets ---"
MINER_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Recompensa")
$CLI generatetoaddress 103 "$MINER_ADDR" > /dev/null
MINER_BAL=$($CLI -rpcwallet=Miner getbalance)
echo "Miner: $MINER_BAL BTC"

EMPLOYER_ADDR=$($CLI -rpcwallet=Empleador getnewaddress "Fondeo")
$CLI -rpcwallet=Miner sendtoaddress "$EMPLOYER_ADDR" 50 > /dev/null
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
EMPLOYER_BAL=$($CLI -rpcwallet=Empleador getbalance)
echo "Empleador: $EMPLOYER_BAL BTC"

# ============================================================
#  TIMELOCK ABSOLUTO
# ============================================================

echo ""
echo "============================================"
echo "  TIMELOCK ABSOLUTO (bloque 500)"
echo "============================================"

# --- 3. Crear transacción salarial con locktime=500 ---
echo ""
echo "--- 3. Creando tx salarial: Empleador → Empleado (40 BTC, locktime=500) ---"

EMPLOYEE_ADDR=$($CLI -rpcwallet=Empleado getnewaddress "Salario")

UTXO=$($CLI -rpcwallet=Empleador listunspent | jq '.[0]')
UTXO_TXID=$(echo "$UTXO" | jq -r '.txid')
UTXO_VOUT=$(echo "$UTXO" | jq -r '.vout')
UTXO_AMT=$(echo "$UTXO" | jq -r '.amount')
CHANGE_ADDR=$($CLI -rpcwallet=Empleador getnewaddress "Cambio salario")
CHANGE_AMT=$(echo "$UTXO_AMT - 40 - 0.0001" | bc)

echo "Input: $UTXO_TXID:$UTXO_VOUT ($UTXO_AMT BTC)"
echo "Output Empleado: 40 BTC → $EMPLOYEE_ADDR"
echo "Output cambio: $CHANGE_AMT BTC → $CHANGE_ADDR"
echo "Locktime: 500 bloques"

# sequence=0xfffffffe permite que locktime surta efecto
SALARY_RAW=$($CLI createrawtransaction \
  "[{\"txid\":\"$UTXO_TXID\",\"vout\":$UTXO_VOUT,\"sequence\":4294967294}]" \
  "[{\"$EMPLOYEE_ADDR\":40},{\"$CHANGE_ADDR\":$CHANGE_AMT}]" \
  500)

SALARY_SIGNED=$($CLI -rpcwallet=Empleador signrawtransactionwithwallet "$SALARY_RAW" | jq -r '.hex')

# --- 4. Intentar transmitir antes del bloque 500 ---
echo ""
echo "--- 4. Intentando transmitir antes del bloque 500 ---"
CURRENT_BLOCK=$($CLI getblockcount)
echo "Bloque actual: $CURRENT_BLOCK"

EARLY_RESULT=$($CLI sendrawtransaction "$SALARY_SIGNED" 2>&1) || true
echo "Resultado: $EARLY_RESULT"
echo ""
echo "# La transacción tiene locktime=500 pero estamos en el bloque $CURRENT_BLOCK."
echo "# El nodo la rechaza con 'non-final' porque no puede incluirse en ningún"
echo "# bloque hasta que la blockchain alcance la altura 500."

# --- 5. Minar hasta bloque 500 y transmitir ---
echo ""
echo "--- 5. Minando hasta el bloque 500 ---"
CURRENT_BLOCK=$($CLI getblockcount)
BLOCKS_NEEDED=$((500 - CURRENT_BLOCK))
echo "Bloques a minar: $BLOCKS_NEEDED"
$CLI generatetoaddress "$BLOCKS_NEEDED" "$MINER_ADDR" > /dev/null
echo "Bloque actual: $($CLI getblockcount)"

SALARY_TXID=$($CLI sendrawtransaction "$SALARY_SIGNED")
echo "Tx salarial transmitida: $SALARY_TXID"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# --- 6. Saldos después del pago ---
echo ""
echo "--- 6. Saldos después del pago salarial ---"
EMPLOYEE_BAL=$($CLI -rpcwallet=Empleado getbalance)
EMPLOYER_BAL=$($CLI -rpcwallet=Empleador getbalance)
echo "Empleado:  $EMPLOYEE_BAL BTC"
echo "Empleador: $EMPLOYER_BAL BTC"

# ============================================================
#  GASTAR CON OP_RETURN
# ============================================================

echo ""
echo "============================================"
echo "  GASTO CON OP_RETURN"
echo "============================================"

# --- 7. Empleado gasta a nueva dirección + OP_RETURN ---
echo ""
echo "--- 7. Empleado gasta fondos + mensaje OP_RETURN ---"

NEW_EMPLOYEE_ADDR=$($CLI -rpcwallet=Empleado getnewaddress "Gasto")
MSG="He recibido mi salario, ahora soy rico"
MSG_HEX=$(echo -n "$MSG" | xxd -p | tr -d '\n')
echo "Mensaje: $MSG"
echo "Hex: $MSG_HEX"

EMP_UTXO=$($CLI -rpcwallet=Empleado listunspent | jq '.[0]')
EMP_TXID=$(echo "$EMP_UTXO" | jq -r '.txid')
EMP_VOUT=$(echo "$EMP_UTXO" | jq -r '.vout')
EMP_AMT=$(echo "$EMP_UTXO" | jq -r '.amount')
SPEND_AMT=$(echo "$EMP_AMT - 0.0001" | bc)

SPEND_RAW=$($CLI createrawtransaction \
  "[{\"txid\":\"$EMP_TXID\",\"vout\":$EMP_VOUT}]" \
  "[{\"$NEW_EMPLOYEE_ADDR\":$SPEND_AMT},{\"data\":\"$MSG_HEX\"}]")

SPEND_SIGNED=$($CLI -rpcwallet=Empleado signrawtransactionwithwallet "$SPEND_RAW" | jq -r '.hex')
SPEND_TXID=$($CLI sendrawtransaction "$SPEND_SIGNED")
echo "Tx de gasto transmitida: $SPEND_TXID"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo ""
echo "--- Verificando OP_RETURN en la transacción ---"
OP_RETURN_DATA=$($CLI getrawtransaction "$SPEND_TXID" true | \
  jq -r '.vout[] | select(.scriptPubKey.type == "nulldata") | .scriptPubKey.hex')
# Hex format: 6a (OP_RETURN) + length_byte + data
# Strip the first 4 hex chars (6a + 1-byte push length)
OP_RETURN_MSG=${OP_RETURN_DATA:4}
DECODED_MSG=$(echo "$OP_RETURN_MSG" | xxd -r -p)
echo "Mensaje decodificado de la blockchain: $DECODED_MSG"

# --- 8. Saldos después del gasto ---
echo ""
echo "--- 8. Saldos después del gasto OP_RETURN ---"
EMPLOYEE_BAL=$($CLI -rpcwallet=Empleado getbalance)
EMPLOYER_BAL=$($CLI -rpcwallet=Empleador getbalance)
echo "Empleado:  $EMPLOYEE_BAL BTC"
echo "Empleador: $EMPLOYER_BAL BTC"

# ============================================================
#  TIMELOCK RELATIVO
# ============================================================

echo ""
echo "============================================"
echo "  TIMELOCK RELATIVO (10 bloques)"
echo "============================================"

# --- 9. Crear tx con timelock relativo (sequence=10) ---
echo ""
echo "--- 9. Creando tx: Empleador → Miner (1 BTC, timelock relativo 10 bloques) ---"

EMPLOYER_UTXO=$($CLI -rpcwallet=Empleador listunspent | jq '.[0]')
E_TXID=$(echo "$EMPLOYER_UTXO" | jq -r '.txid')
E_VOUT=$(echo "$EMPLOYER_UTXO" | jq -r '.vout')
E_AMT=$(echo "$EMPLOYER_UTXO" | jq -r '.amount')
MINER_RECV=$($CLI -rpcwallet=Miner getnewaddress "Pago relativo")
E_CHANGE_ADDR=$($CLI -rpcwallet=Empleador getnewaddress "Cambio relativo")
E_CHANGE=$(echo "$E_AMT - 1 - 0.0001" | bc)

echo "Input: $E_TXID:$E_VOUT ($E_AMT BTC)"
echo "Sequence: 10 (timelock relativo de 10 bloques)"

REL_RAW=$($CLI createrawtransaction \
  "[{\"txid\":\"$E_TXID\",\"vout\":$E_VOUT,\"sequence\":10}]" \
  "[{\"$MINER_RECV\":1},{\"$E_CHANGE_ADDR\":$E_CHANGE}]")

REL_SIGNED=$($CLI -rpcwallet=Empleador signrawtransactionwithwallet "$REL_RAW" | jq -r '.hex')

# --- 10. Intentar transmitir (debe fallar) ---
echo ""
echo "--- 10. Intentando transmitir antes de que pasen 10 bloques ---"

UTXO_BLOCK=$($CLI getrawtransaction "$E_TXID" true | jq -r '.blockhash')
UTXO_HEIGHT=$($CLI getblock "$UTXO_BLOCK" | jq '.height')
CURRENT_BLOCK=$($CLI getblockcount)
echo "UTXO confirmado en bloque: $UTXO_HEIGHT"
echo "Bloque actual: $CURRENT_BLOCK"
echo "Bloques transcurridos: $((CURRENT_BLOCK - UTXO_HEIGHT))"

REL_EARLY=$($CLI sendrawtransaction "$REL_SIGNED" 2>&1) || true
echo "Resultado: $REL_EARLY"
echo ""
echo "# El input tiene sequence=10, lo que activa BIP 68 (timelock relativo)."
echo "# El UTXO se confirmó hace menos de 10 bloques, así que la tx es 'non-BIP68-final'."
echo "# Debemos esperar a que pasen 10 bloques desde la confirmación del UTXO."

# --- 11. Minar 10 bloques y transmitir ---
echo ""
echo "--- 11. Minando 10 bloques y transmitiendo ---"
BLOCKS_TO_MINE=$((UTXO_HEIGHT + 10 - CURRENT_BLOCK))
if [ "$BLOCKS_TO_MINE" -gt 0 ]; then
  $CLI generatetoaddress "$BLOCKS_TO_MINE" "$MINER_ADDR" > /dev/null
fi
echo "Bloque actual: $($CLI getblockcount)"

REL_TXID=$($CLI sendrawtransaction "$REL_SIGNED")
echo "Tx relativa transmitida: $REL_TXID"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# --- 12. Saldos finales ---
echo ""
echo "--- 12. Saldos finales ---"
EMPLOYEE_FINAL=$($CLI -rpcwallet=Empleado getbalance)
EMPLOYER_FINAL=$($CLI -rpcwallet=Empleador getbalance)
MINER_FINAL=$($CLI -rpcwallet=Miner getbalance)

echo "Empleado:  $EMPLOYEE_FINAL BTC"
echo "Empleador: $EMPLOYER_FINAL BTC"
echo "Miner:     $MINER_FINAL BTC"
echo ""
echo "Resumen:"
echo "  - Timelock absoluto (locktime=500): pagó 40 BTC al Empleado después del bloque 500"
echo "  - OP_RETURN: '$MSG' grabado permanentemente en la blockchain"
echo "  - Timelock relativo (sequence=10): pagó 1 BTC a Miner después de 10 bloques de espera"
