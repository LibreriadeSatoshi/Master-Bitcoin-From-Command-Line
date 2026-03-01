#!/usr/bin/env bash
# Ejercicio Semana 3 — Maestros de Bitcoin desde la línea de comandos
# Librería de Satoshi — MBFCL
#
# Simula una transferencia multisig 2-de-2 entre Alice y Bob:
#   Setup:  Crea wallets, fondea, construye multisig con descriptors,
#           fondea multisig con PSBT (10 BTC de cada uno)
#   Settle: Gasta desde multisig enviando 3 BTC a Alice via PSBT

set -e

CLI="bitcoin-cli -regtest"

echo "============================================"
echo "  EJERCICIO SEMANA 3 — Multisig y PSBTs"
echo "============================================"

# ============================================================
#  SETUP MULTISIG
# ============================================================

# --- 1. Crear wallets ---
echo ""
echo "--- 1. Creando wallets Miner, Alice y Bob ---"
$CLI createwallet "Miner"  > /dev/null 2>&1 || $CLI loadwallet "Miner"  > /dev/null 2>&1 || true
$CLI createwallet "Alice"  > /dev/null 2>&1 || $CLI loadwallet "Alice"  > /dev/null 2>&1 || true
$CLI createwallet "Bob"    > /dev/null 2>&1 || $CLI loadwallet "Bob"    > /dev/null 2>&1 || true
echo "Wallets: Miner, Alice, Bob"

# --- 2. Fondear wallets ---
echo ""
echo "--- 2. Fondeando wallets ---"
MINER_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Recompensa")
$CLI generatetoaddress 103 "$MINER_ADDR" > /dev/null
MINER_BAL=$($CLI -rpcwallet=Miner getbalance)
echo "Miner: $MINER_BAL BTC (103 bloques minados, 3 coinbases maduras)"

ALICE_ADDR=$($CLI -rpcwallet=Alice getnewaddress "Fondeo")
BOB_ADDR=$($CLI -rpcwallet=Bob getnewaddress "Fondeo")
$CLI -rpcwallet=Miner sendtoaddress "$ALICE_ADDR" 15 > /dev/null
$CLI -rpcwallet=Miner sendtoaddress "$BOB_ADDR" 15 > /dev/null
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

ALICE_BAL=$($CLI -rpcwallet=Alice getbalance)
BOB_BAL=$($CLI -rpcwallet=Bob getbalance)
echo "Alice: $ALICE_BAL BTC"
echo "Bob:   $BOB_BAL BTC"

# --- 3. Construir descriptor multisig 2-de-2 ---
echo ""
echo "--- 3. Construyendo descriptor multisig 2-de-2 ---"

ALICE_PK=$($CLI -rpcwallet=Alice getaddressinfo "$ALICE_ADDR" | jq -r '.pubkey')
BOB_PK=$($CLI -rpcwallet=Bob getaddressinfo "$BOB_ADDR" | jq -r '.pubkey')
echo "Alice pubkey: $ALICE_PK"
echo "Bob pubkey:   $BOB_PK"

RAW_DESC="wsh(multi(2,$ALICE_PK,$BOB_PK))"
DESC_INFO=$($CLI getdescriptorinfo "$RAW_DESC")
DESC=$(echo "$DESC_INFO" | jq -r '.descriptor')
echo "Descriptor: $DESC"

# --- 4. Crear wallet Multisig (watch-only, descriptors) ---
echo ""
echo "--- 4. Creando wallet Multisig (watch-only) ---"

$CLI createwallet "Multisig" true true "" false true > /dev/null 2>&1 || \
  $CLI loadwallet "Multisig" > /dev/null 2>&1 || true

IMPORT_RESULT=$($CLI -rpcwallet=Multisig importdescriptors \
  "[{\"desc\":\"$DESC\",\"timestamp\":\"now\"}]")
echo "Import: $(echo "$IMPORT_RESULT" | jq -r '.[0].success')"

MULTISIG_ADDR=$($CLI deriveaddresses "$DESC" | jq -r '.[0]')
echo "Dirección multisig: $MULTISIG_ADDR"

# --- 5. Crear PSBT para fondear multisig (10 BTC de cada uno) ---
echo ""
echo "--- 5. Fondeando multisig con PSBT (10 BTC de Alice + 10 BTC de Bob) ---"

ALICE_UTXO=$($CLI -rpcwallet=Alice listunspent | jq '.[0]')
ALICE_TXID=$(echo "$ALICE_UTXO" | jq -r '.txid')
ALICE_VOUT=$(echo "$ALICE_UTXO" | jq -r '.vout')
ALICE_AMT=$(echo "$ALICE_UTXO" | jq -r '.amount')

BOB_UTXO=$($CLI -rpcwallet=Bob listunspent | jq '.[0]')
BOB_TXID=$(echo "$BOB_UTXO" | jq -r '.txid')
BOB_VOUT=$(echo "$BOB_UTXO" | jq -r '.vout')
BOB_AMT=$(echo "$BOB_UTXO" | jq -r '.amount')

echo "Input Alice: $ALICE_TXID:$ALICE_VOUT ($ALICE_AMT BTC)"
echo "Input Bob:   $BOB_TXID:$BOB_VOUT ($BOB_AMT BTC)"

ALICE_CHANGE_ADDR=$($CLI -rpcwallet=Alice getnewaddress "Cambio fondeo")
BOB_CHANGE_ADDR=$($CLI -rpcwallet=Bob getnewaddress "Cambio fondeo")

ALICE_CHANGE=$(echo "$ALICE_AMT - 10 - 0.00005" | bc)
BOB_CHANGE=$(echo "$BOB_AMT - 10 - 0.00005" | bc)

echo "Output multisig: 20 BTC"
echo "Output cambio Alice: $ALICE_CHANGE BTC → $ALICE_CHANGE_ADDR"
echo "Output cambio Bob:   $BOB_CHANGE BTC → $BOB_CHANGE_ADDR"
echo "Fee total: 0.0001 BTC (0.00005 cada uno)"

FUND_PSBT=$($CLI createpsbt \
  "[{\"txid\":\"$ALICE_TXID\",\"vout\":$ALICE_VOUT},
    {\"txid\":\"$BOB_TXID\",\"vout\":$BOB_VOUT}]" \
  "[{\"$MULTISIG_ADDR\":20},
    {\"$ALICE_CHANGE_ADDR\":$ALICE_CHANGE},
    {\"$BOB_CHANGE_ADDR\":$BOB_CHANGE}]")

echo ""
echo "PSBT creada (sin firmas)"

# --- 6. Alice firma, Bob firma, combinar, finalizar ---
echo ""
echo "--- 6. Firmando PSBT de fondeo ---"

ALICE_PROCESSED=$($CLI -rpcwallet=Alice walletprocesspsbt "$FUND_PSBT")
ALICE_SIGNED=$(echo "$ALICE_PROCESSED" | jq -r '.psbt')
ALICE_COMPLETE=$(echo "$ALICE_PROCESSED" | jq -r '.complete')
echo "Alice firmó — complete: $ALICE_COMPLETE"

BOB_PROCESSED=$($CLI -rpcwallet=Bob walletprocesspsbt "$FUND_PSBT")
BOB_SIGNED=$(echo "$BOB_PROCESSED" | jq -r '.psbt')
BOB_COMPLETE=$(echo "$BOB_PROCESSED" | jq -r '.complete')
echo "Bob firmó   — complete: $BOB_COMPLETE"

COMBINED=$($CLI combinepsbt "[\"$ALICE_SIGNED\",\"$BOB_SIGNED\"]")
echo "PSBTs combinadas"

FINAL=$($CLI finalizepsbt "$COMBINED")
FINAL_COMPLETE=$(echo "$FINAL" | jq -r '.complete')
FINAL_HEX=$(echo "$FINAL" | jq -r '.hex')
echo "Finalizada — complete: $FINAL_COMPLETE"

FUND_TXID=$($CLI sendrawtransaction "$FINAL_HEX")
echo "Tx de fondeo transmitida: $FUND_TXID"

# --- 7. Confirmar y mostrar saldos ---
echo ""
echo "--- 7. Confirmando fondeo (minando bloques) ---"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

ALICE_BAL=$($CLI -rpcwallet=Alice getbalance)
BOB_BAL=$($CLI -rpcwallet=Bob getbalance)
MS_BAL=$($CLI -rpcwallet=Multisig getbalance)
echo "Saldo Alice:    $ALICE_BAL BTC"
echo "Saldo Bob:      $BOB_BAL BTC"
echo "Saldo Multisig: $MS_BAL BTC"

# ============================================================
#  LIQUIDAR MULTISIG
# ============================================================

echo ""
echo "============================================"
echo "  LIQUIDAR MULTISIG"
echo "============================================"

# --- 8. Crear PSBT para gastar desde multisig (3 BTC a Alice) ---
echo ""
echo "--- 8. Creando PSBT de gasto (3 BTC a Alice) ---"

MS_UTXO=$($CLI -rpcwallet=Multisig listunspent | jq '.[0]')
MS_TXID=$(echo "$MS_UTXO" | jq -r '.txid')
MS_VOUT=$(echo "$MS_UTXO" | jq -r '.vout')
MS_AMT=$(echo "$MS_UTXO" | jq -r '.amount')
echo "Input multisig: $MS_TXID:$MS_VOUT ($MS_AMT BTC)"

ALICE_RECV=$($CLI -rpcwallet=Alice getnewaddress "Liquidacion")
MS_CHANGE=$(echo "$MS_AMT - 3 - 0.0001" | bc)
echo "Output Alice: 3 BTC → $ALICE_RECV"
echo "Output cambio multisig: $MS_CHANGE BTC → $MULTISIG_ADDR"
echo "Fee: 0.0001 BTC"

SPEND_PSBT=$($CLI -rpcwallet=Multisig createpsbt \
  "[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT}]" \
  "[{\"$ALICE_RECV\":3},{\"$MULTISIG_ADDR\":$MS_CHANGE}]")

echo "PSBT de gasto creada"

# Update PSBT with UTXO data from the Multisig wallet
SPEND_PSBT=$($CLI -rpcwallet=Multisig walletprocesspsbt "$SPEND_PSBT" | jq -r '.psbt')

# --- 9. Alice firma ---
echo ""
echo "--- 9. Alice firma PSBT de gasto ---"
ALICE_SPEND_RESULT=$($CLI -rpcwallet=Alice walletprocesspsbt "$SPEND_PSBT")
ALICE_SPEND=$(echo "$ALICE_SPEND_RESULT" | jq -r '.psbt')
ALICE_SPEND_COMPLETE=$(echo "$ALICE_SPEND_RESULT" | jq -r '.complete')
echo "Alice firmó — complete: $ALICE_SPEND_COMPLETE"

# --- 10. Bob firma ---
echo ""
echo "--- 10. Bob firma PSBT de gasto ---"
BOB_SPEND_RESULT=$($CLI -rpcwallet=Bob walletprocesspsbt "$SPEND_PSBT")
BOB_SPEND=$(echo "$BOB_SPEND_RESULT" | jq -r '.psbt')
BOB_SPEND_COMPLETE=$(echo "$BOB_SPEND_RESULT" | jq -r '.complete')
echo "Bob firmó   — complete: $BOB_SPEND_COMPLETE"

# --- 11. Combinar, finalizar y transmitir ---
echo ""
echo "--- 11. Combinando firmas, finalizando y transmitiendo ---"
SPEND_COMBINED=$($CLI combinepsbt "[\"$ALICE_SPEND\",\"$BOB_SPEND\"]")
SPEND_FINAL=$($CLI finalizepsbt "$SPEND_COMBINED")
SPEND_COMPLETE=$(echo "$SPEND_FINAL" | jq -r '.complete')
SPEND_HEX=$(echo "$SPEND_FINAL" | jq -r '.hex')
echo "Finalizada — complete: $SPEND_COMPLETE"

SPEND_TXID=$($CLI sendrawtransaction "$SPEND_HEX")
echo "Tx de gasto transmitida: $SPEND_TXID"

# --- 12. Confirmar y saldos finales ---
echo ""
echo "--- 12. Saldos finales ---"
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

ALICE_FINAL=$($CLI -rpcwallet=Alice getbalance)
BOB_FINAL=$($CLI -rpcwallet=Bob getbalance)
MS_FINAL=$($CLI -rpcwallet=Multisig getbalance)

echo "Alice:    $ALICE_FINAL BTC"
echo "Bob:      $BOB_FINAL BTC"
echo "Multisig: $MS_FINAL BTC"
echo ""
echo "Alice recibió 3 BTC de la liquidación del multisig."
echo "Bob no recibió fondos en esta liquidación."
echo "El multisig retiene el resto como cambio."
