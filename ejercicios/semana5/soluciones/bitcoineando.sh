#!/usr/bin/env bash
# Ejercicio Semana 5 — Maestros de Bitcoin desde la línea de comandos
# Librería de Satoshi — MBFCL
#
# Condiciones de gasto con miniscript:
#   Política: or(and(pk(Alice),pk(Bob)), and(pk(Recovery),older(10)))
#   - Camino A: Alice + Bob firman (multisig 2-de-2) — gasto normal
#   - Camino B: Recovery firma sola después de 10 bloques — cláusula de escape
#
# Caso de uso: custodia compartida Alice/Bob con recovery key por timeout.
# Si Alice y Bob no cooperan, la Recovery key puede rescatar fondos después de 10 bloques.

set -e

CLI="bitcoin-cli -regtest"

echo "============================================"
echo "  EJERCICIO SEMANA 5 — Miniscript"
echo "============================================"
echo ""
echo "Política: or(and(pk(Alice),pk(Bob)), and(pk(Recovery),older(10)))"
echo ""
echo "Dos caminos de gasto:"
echo "  A) Alice + Bob firman juntos (multisig 2-de-2)"
echo "  B) Recovery firma sola después de 10 bloques (timeout escape)"
echo ""
echo "Caso de uso: custodia compartida con recovery key."
echo "Si Alice y Bob no cooperan, Recovery puede rescatar fondos tras el timeout."

# ============================================================
#  SETUP
# ============================================================

# --- 1. Crear wallets ---
echo ""
echo "--- 1. Creando wallets ---"
$CLI createwallet "Miner"    > /dev/null 2>&1 || $CLI loadwallet "Miner"    > /dev/null 2>&1 || true
$CLI createwallet "Alice"    > /dev/null 2>&1 || $CLI loadwallet "Alice"    > /dev/null 2>&1 || true
$CLI createwallet "Bob"      > /dev/null 2>&1 || $CLI loadwallet "Bob"      > /dev/null 2>&1 || true
$CLI createwallet "Recovery" > /dev/null 2>&1 || $CLI loadwallet "Recovery" > /dev/null 2>&1 || true
echo "Wallets: Miner, Alice, Bob, Recovery"

# --- 2. Fondear ---
echo ""
echo "--- 2. Fondeando ---"
MINER_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Recompensa")
$CLI generatetoaddress 103 "$MINER_ADDR" > /dev/null

ALICE_ADDR=$($CLI -rpcwallet=Alice getnewaddress "Fondeo")
BOB_ADDR=$($CLI -rpcwallet=Bob getnewaddress "Fondeo")
REC_ADDR=$($CLI -rpcwallet=Recovery getnewaddress "Fondeo")
$CLI -rpcwallet=Miner sendtoaddress "$ALICE_ADDR" 50 > /dev/null
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "Alice: $($CLI -rpcwallet=Alice getbalance) BTC"

# --- 3. Obtener pubkeys ---
echo ""
echo "--- 3. Obteniendo pubkeys ---"
ALICE_PK=$($CLI -rpcwallet=Alice getaddressinfo "$ALICE_ADDR" | jq -r '.pubkey')
BOB_PK=$($CLI -rpcwallet=Bob getaddressinfo "$BOB_ADDR" | jq -r '.pubkey')
REC_PK=$($CLI -rpcwallet=Recovery getaddressinfo "$REC_ADDR" | jq -r '.pubkey')
echo "Alice:    $ALICE_PK"
echo "Bob:      $BOB_PK"
echo "Recovery: $REC_PK"

# --- 4. Construir descriptor con miniscript ---
echo ""
echo "--- 4. Construyendo descriptor miniscript ---"

# or_d(multi(2,Alice,Bob), and_v(v:pk(Recovery),older(10)))
MINISCRIPT="or_d(multi(2,$ALICE_PK,$BOB_PK),and_v(v:pk($REC_PK),older(10)))"
RAW_DESC="wsh($MINISCRIPT)"
echo "Miniscript: or_d(multi(2,Alice,Bob),and_v(v:pk(Recovery),older(10)))"

DESC_INFO=$($CLI getdescriptorinfo "$RAW_DESC")
DESC=$(echo "$DESC_INFO" | jq -r '.descriptor')
echo "Descriptor: $DESC"

# --- 5. Crear wallet Contrato e importar ---
echo ""
echo "--- 5. Creando wallet Contrato (watch-only) ---"
$CLI createwallet "Contrato" true true "" false true > /dev/null 2>&1 || \
  $CLI loadwallet "Contrato" > /dev/null 2>&1 || true

IMPORT_RESULT=$($CLI -rpcwallet=Contrato importdescriptors \
  "[{\"desc\":\"$DESC\",\"timestamp\":\"now\"}]")
echo "Import: $(echo "$IMPORT_RESULT" | jq -r '.[0].success')"

CONTRACT_ADDR=$($CLI deriveaddresses "$DESC" | jq -r '.[0]')
echo "Dirección del contrato: $CONTRACT_ADDR"

# --- 6. Fondear el contrato (2 UTXOs para probar ambos caminos) ---
echo ""
echo "--- 6. Fondeando contrato (2 UTXOs de 10 BTC) ---"
$CLI -rpcwallet=Alice sendtoaddress "$CONTRACT_ADDR" 10 > /dev/null
$CLI -rpcwallet=Alice sendtoaddress "$CONTRACT_ADDR" 10 > /dev/null
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
CONTRACT_BAL=$($CLI -rpcwallet=Contrato getbalance)
echo "Contrato: $CONTRACT_BAL BTC (2 UTXOs)"

# ============================================================
#  CAMINO A: MULTISIG (Alice + Bob)
# ============================================================

echo ""
echo "============================================"
echo "  CAMINO A: Multisig (Alice + Bob)"
echo "============================================"

echo ""
echo "--- 7. Gastando UTXO #1 con firmas de Alice + Bob ---"

UTXO_A=$($CLI -rpcwallet=Contrato listunspent | jq '.[0]')
UA_TXID=$(echo "$UTXO_A" | jq -r '.txid')
UA_VOUT=$(echo "$UTXO_A" | jq -r '.vout')
UA_AMT=$(echo "$UTXO_A" | jq -r '.amount')
echo "Input: $UA_TXID:$UA_VOUT ($UA_AMT BTC)"

ALICE_RECV_A=$($CLI -rpcwallet=Alice getnewaddress "Camino A")

PSBT_A=$($CLI createpsbt \
  "[{\"txid\":\"$UA_TXID\",\"vout\":$UA_VOUT}]" \
  "[{\"$ALICE_RECV_A\":9.9999}]")

PSBT_A=$($CLI -rpcwallet=Contrato walletprocesspsbt "$PSBT_A" | jq -r '.psbt')

ALICE_A=$($CLI -rpcwallet=Alice walletprocesspsbt "$PSBT_A")
ALICE_A_PSBT=$(echo "$ALICE_A" | jq -r '.psbt')
echo "Alice firmó — complete: $(echo "$ALICE_A" | jq -r '.complete')"

BOB_A=$($CLI -rpcwallet=Bob walletprocesspsbt "$PSBT_A")
BOB_A_PSBT=$(echo "$BOB_A" | jq -r '.psbt')
echo "Bob firmó   — complete: $(echo "$BOB_A" | jq -r '.complete')"

COMBINED_A=$($CLI combinepsbt "[\"$ALICE_A_PSBT\",\"$BOB_A_PSBT\"]")
FINAL_A=$($CLI finalizepsbt "$COMBINED_A")
echo "Finalizada — complete: $(echo "$FINAL_A" | jq -r '.complete')"

HEX_A=$(echo "$FINAL_A" | jq -r '.hex')
TXID_A=$($CLI sendrawtransaction "$HEX_A")
echo "Tx camino A transmitida: $TXID_A"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo ""
echo "Condición cumplida: MULTISIG 2-de-2 (Alice + Bob firmaron juntos)"

# ============================================================
#  CAMINO B: TIMEOUT (Recovery sola + older(10))
# ============================================================

echo ""
echo "============================================"
echo "  CAMINO B: Timeout (Recovery + older(10))"
echo "============================================"

# --- 8. Intentar gastar con Recovery antes del timeout ---
echo ""
echo "--- 8. Intentando gastar con Recovery (sin esperar timeout) ---"

UTXO_B=$($CLI -rpcwallet=Contrato listunspent | jq '.[0]')
UB_TXID=$(echo "$UTXO_B" | jq -r '.txid')
UB_VOUT=$(echo "$UTXO_B" | jq -r '.vout')
UB_AMT=$(echo "$UTXO_B" | jq -r '.amount')
echo "Input: $UB_TXID:$UB_VOUT ($UB_AMT BTC)"

REC_RECV=$($CLI -rpcwallet=Recovery getnewaddress "Camino B")

PSBT_B=$($CLI createpsbt \
  "[{\"txid\":\"$UB_TXID\",\"vout\":$UB_VOUT,\"sequence\":10}]" \
  "[{\"$REC_RECV\":9.9999}]")

PSBT_B=$($CLI -rpcwallet=Contrato walletprocesspsbt "$PSBT_B" | jq -r '.psbt')

REC_B=$($CLI -rpcwallet=Recovery walletprocesspsbt "$PSBT_B")
REC_B_PSBT=$(echo "$REC_B" | jq -r '.psbt')
REC_B_COMPLETE=$(echo "$REC_B" | jq -r '.complete')
echo "Recovery firmó — complete: $REC_B_COMPLETE"

FINAL_B_TRY=$($CLI finalizepsbt "$REC_B_PSBT")
FINAL_B_TRY_OK=$(echo "$FINAL_B_TRY" | jq -r '.complete')
echo "Finalización: complete: $FINAL_B_TRY_OK"

if [ "$FINAL_B_TRY_OK" = "true" ]; then
  HEX_B_TRY=$(echo "$FINAL_B_TRY" | jq -r '.hex')
  EARLY_RESULT=$($CLI sendrawtransaction "$HEX_B_TRY" 2>&1) || true
  echo "Broadcast: $EARLY_RESULT"
  echo ""
  echo "# La tx se finalizó pero sequence=10 impone BIP 68 (timelock relativo)."
  echo "# El nodo rechaza: 'non-BIP68-final' hasta que pasen 10 bloques."
else
  echo ""
  echo "# No se puede finalizar aún: el timeout older(10) no se ha cumplido."
fi

# --- 9. Minar 10 bloques y gastar ---
echo ""
echo "--- 9. Minando 10 bloques para cumplir older(10) ---"
$CLI generatetoaddress 10 "$MINER_ADDR" > /dev/null
echo "Bloque actual: $($CLI getblockcount)"

PSBT_B2=$($CLI createpsbt \
  "[{\"txid\":\"$UB_TXID\",\"vout\":$UB_VOUT,\"sequence\":10}]" \
  "[{\"$REC_RECV\":9.9999}]")

PSBT_B2=$($CLI -rpcwallet=Contrato walletprocesspsbt "$PSBT_B2" | jq -r '.psbt')

REC_B2=$($CLI -rpcwallet=Recovery walletprocesspsbt "$PSBT_B2")
REC_B2_PSBT=$(echo "$REC_B2" | jq -r '.psbt')
echo "Recovery firmó — complete: $(echo "$REC_B2" | jq -r '.complete')"

FINAL_B2=$($CLI finalizepsbt "$REC_B2_PSBT")
echo "Finalizada — complete: $(echo "$FINAL_B2" | jq -r '.complete')"

HEX_B2=$(echo "$FINAL_B2" | jq -r '.hex')
TXID_B=$($CLI sendrawtransaction "$HEX_B2")
echo "Tx camino B transmitida: $TXID_B"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo ""
echo "Condición cumplida: TIMEOUT — Recovery firmó sola después de 10 bloques"

# --- 10. Saldos finales ---
echo ""
echo "--- 10. Saldos finales ---"
ALICE_FINAL=$($CLI -rpcwallet=Alice getbalance)
REC_FINAL=$($CLI -rpcwallet=Recovery getbalance)
CONTRACT_FINAL=$($CLI -rpcwallet=Contrato getbalance)

echo "Alice:    $ALICE_FINAL BTC"
echo "Recovery: $REC_FINAL BTC"
echo "Contrato: $CONTRACT_FINAL BTC"
echo ""
echo "Resumen:"
echo "  Camino A (multisig): Alice + Bob gastaron UTXO #1 → 9.9999 BTC a Alice"
echo "  Camino B (timeout):  Recovery gastó UTXO #2 tras 10 bloques → 9.9999 BTC a Recovery"
echo "  Contrato: vacío (ambos UTXOs gastados por caminos distintos)"
