#!/usr/bin/env bash
# Ejercicio Semana 2 — Maestros de Bitcoin desde la línea de comandos
# Librería de Satoshi — MBFCL
#
# Demuestra que RBF y CPFP no pueden usarse juntos:
# 1. Crea parent tx con RBF señalado
# 2. Crea child tx (CPFP) gastando el cambio del parent
# 3. Reemplaza el parent con RBF → el child se invalida

set -e

CLI="bitcoin-cli -regtest"

echo "============================================"
echo "  EJERCICIO SEMANA 2 — RBF y CPFP"
echo "============================================"

# --- 1. Crear wallets ---
echo ""
echo "--- 1. Creando wallets Miner y Trader ---"
$CLI createwallet "Miner" > /dev/null 2>&1 || $CLI loadwallet "Miner" > /dev/null 2>&1 || true
$CLI createwallet "Trader" > /dev/null 2>&1 || $CLI loadwallet "Trader" > /dev/null 2>&1 || true

# --- 2. Fondear Miner con al menos 150 BTC ---
echo "--- 2. Fondeando Miner con 150 BTC (minando 103 bloques) ---"
MINER_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
$CLI generatetoaddress 103 "$MINER_ADDR" > /dev/null
MINER_BALANCE=$($CLI -rpcwallet=Miner getbalance)
echo "Saldo Miner: $MINER_BALANCE BTC"

# --- 3. Construir parent tx con RBF ---
echo ""
echo "--- 3. Construyendo transacción parent con RBF ---"

TRADER_ADDR=$($CLI -rpcwallet=Trader getnewaddress "Recibido")
MINER_CHANGE_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Cambio parent")

UTXOS=$($CLI -rpcwallet=Miner listunspent | jq '[.[] | select(.amount == 50)] | .[0:2]')
UTXO1_TXID=$(echo "$UTXOS" | jq -r '.[0].txid')
UTXO1_VOUT=$(echo "$UTXOS" | jq -r '.[0].vout')
UTXO2_TXID=$(echo "$UTXOS" | jq -r '.[1].txid')
UTXO2_VOUT=$(echo "$UTXOS" | jq -r '.[1].vout')

echo "Input 0: $UTXO1_TXID:$UTXO1_VOUT (50 BTC)"
echo "Input 1: $UTXO2_TXID:$UTXO2_VOUT (50 BTC)"
echo "Output 0: $TRADER_ADDR → 70 BTC"
echo "Output 1: $MINER_CHANGE_ADDR → 29.99999 BTC (cambio)"
echo "Fee: 0.00001 BTC (1000 sats)"
echo "RBF: señalado (sequence=1)"

PARENT_RAW=$($CLI -rpcwallet=Miner createrawtransaction \
  '[{"txid":"'"$UTXO1_TXID"'","vout":'"$UTXO1_VOUT"',"sequence":1},
    {"txid":"'"$UTXO2_TXID"'","vout":'"$UTXO2_VOUT"',"sequence":1}]' \
  '[{"'"$TRADER_ADDR"'":70},{"'"$MINER_CHANGE_ADDR"'":29.99999}]')

# --- 4. Firmar y transmitir parent (sin minar) ---
echo ""
echo "--- 4. Firmando y transmitiendo parent (no confirmada) ---"
PARENT_SIGNED=$($CLI -rpcwallet=Miner signrawtransactionwithwallet "$PARENT_RAW" | jq -r '.hex')
PARENT_TXID=$($CLI sendrawtransaction "$PARENT_SIGNED")
echo "Parent txid: $PARENT_TXID"

# --- 5. Consultar mempool y construir JSON ---
echo ""
echo "--- 5. Detalles del parent en la mempool ---"

MEMPOOL_ENTRY=$($CLI getmempoolentry "$PARENT_TXID")
DECODED=$($CLI decoderawtransaction "$PARENT_SIGNED")

PARENT_WEIGHT=$(echo "$MEMPOOL_ENTRY" | jq '.vsize')
PARENT_FEES=$(echo "$MEMPOOL_ENTRY" | jq '.fees.base')

PARENT_JSON=$(jq -n \
  --arg utxo1_txid "$UTXO1_TXID" \
  --arg utxo1_vout "$UTXO1_VOUT" \
  --arg utxo2_txid "$UTXO2_TXID" \
  --arg utxo2_vout "$UTXO2_VOUT" \
  --arg miner_spk "$(echo "$DECODED" | jq -r '.vout[1].scriptPubKey.hex')" \
  --arg miner_amt "$(echo "$DECODED" | jq -r '.vout[1].value')" \
  --arg trader_spk "$(echo "$DECODED" | jq -r '.vout[0].scriptPubKey.hex')" \
  --arg trader_amt "$(echo "$DECODED" | jq -r '.vout[0].value')" \
  --arg fees "$PARENT_FEES" \
  --arg weight "$PARENT_WEIGHT" \
  '{
    input: [
      {txid: $utxo1_txid, vout: $utxo1_vout},
      {txid: $utxo2_txid, vout: $utxo2_vout}
    ],
    output: [
      {script_pubkey: $miner_spk, amount: $miner_amt},
      {script_pubkey: $trader_spk, amount: $trader_amt}
    ],
    Fees: $fees,
    Weight: $weight
  }')

# --- 6. Imprimir el JSON ---
echo ""
echo "--- 6. JSON de la transacción parent ---"
echo "$PARENT_JSON" | jq .

# --- 7. Crear child tx (CPFP) ---
echo ""
echo "--- 7. Creando transacción child (CPFP) ---"

MINER_CHILD_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Child destino")

PARENT_CHANGE_VOUT=$(echo "$DECODED" | jq '[.vout[] | select(.value == 29.99999)] | .[0].n')

CHILD_RAW=$($CLI -rpcwallet=Miner createrawtransaction \
  '[{"txid":"'"$PARENT_TXID"'","vout":'"$PARENT_CHANGE_VOUT"'}]' \
  '[{"'"$MINER_CHILD_ADDR"'":29.99998}]')

CHILD_SIGNED=$($CLI -rpcwallet=Miner signrawtransactionwithwallet "$CHILD_RAW" | jq -r '.hex')
CHILD_TXID=$($CLI sendrawtransaction "$CHILD_SIGNED")
echo "Child txid: $CHILD_TXID"

# --- 8. getmempoolentry del child ---
echo ""
echo "--- 8. Child en la mempool (antes de RBF) ---"
CHILD_MEMPOOL_BEFORE=$($CLI getmempoolentry "$CHILD_TXID")
echo "$CHILD_MEMPOOL_BEFORE" | jq .

# --- 9. RBF: reemplazar el parent con fee +10000 sats ---
echo ""
echo "--- 9. Reemplazando parent con RBF (+10000 sats de fee) ---"

RBF_RAW=$($CLI -rpcwallet=Miner createrawtransaction \
  '[{"txid":"'"$UTXO1_TXID"'","vout":'"$UTXO1_VOUT"',"sequence":2},
    {"txid":"'"$UTXO2_TXID"'","vout":'"$UTXO2_VOUT"',"sequence":2}]' \
  '[{"'"$TRADER_ADDR"'":70},{"'"$MINER_CHANGE_ADDR"'":29.99989}]')

# --- 10. Firmar y transmitir el reemplazo ---
echo ""
echo "--- 10. Firmando y transmitiendo reemplazo ---"
RBF_SIGNED=$($CLI -rpcwallet=Miner signrawtransactionwithwallet "$RBF_RAW" | jq -r '.hex')
RBF_TXID=$($CLI sendrawtransaction "$RBF_SIGNED")
echo "RBF txid: $RBF_TXID"
echo "(El parent original $PARENT_TXID fue reemplazado)"

# --- 11. getmempoolentry del child después de RBF ---
echo ""
echo "--- 11. Child en la mempool (después de RBF) ---"
CHILD_MEMPOOL_AFTER=$($CLI getmempoolentry "$CHILD_TXID" 2>&1) || true
echo "$CHILD_MEMPOOL_AFTER"

# --- 12. Explicación ---
echo ""
echo "--- 12. Explicación ---"
echo ""
echo "Antes del RBF, el child estaba en la mempool con:"
echo "  - depends: [$PARENT_TXID]"
echo "  - ancestorcount: 2"
echo ""
echo "Después del RBF, el child fue EXPULSADO de la mempool."
echo "Razón: al reemplazar el parent original por una nueva transacción (RBF),"
echo "el parent original desapareció de la mempool. El child gastaba una salida"
echo "de ese parent original (vout $PARENT_CHANGE_VOUT). Esa salida ya no existe"
echo "en la mempool. Sin input válido, el child es inválido y se descarta."
echo ""
echo "Conclusión: RBF y CPFP son mutuamente excluyentes."
echo "Si reemplazas el parent, destruyes cualquier child que dependa de él."
