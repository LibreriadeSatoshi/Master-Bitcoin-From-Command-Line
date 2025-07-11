#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Semana 2 – Parent + Child + RBF en regtest
# ---------------------------------------------------------------------------
# Flujo:
#   1.  Prepara wallets Miner y Trader y mina 103 bloques (3 recompensas maduras)
#   2.  Parent  : 2 × 50 BTC  → 70 BTC (Trader) + 29.99999 BTC (Miner)  [RBF]
#   3.  Child   : gasta la salida de cambio (vout 1) → 29.99998 BTC (Miner)
#   4.  RBF     : retransmite Parent con +10 000 sat de fee (cambio 29.99989 BTC)
#   5.  Muestra cómo el Child desaparece del mempool al invalidarse su input
# ---------------------------------------------------------------------------
set -euo pipefail

BCLI="bitcoin-cli -regtest"

#0) Función para asegurar que la wallet exista y esté cargada
ensure_wallet() {
  local NAME="$1"
  if ! $BCLI -rpcwallet="$NAME" getwalletinfo >/dev/null 2>&1; then
    # Intenta crearla; si ya existe, cárgala
    $BCLI createwallet "$NAME" load_on_startup=false >/dev/null 2>&1 || \
    $BCLI loadwallet  "$NAME" >/dev/null
  fi
}

#1) Crear / cargar wallets
ensure_wallet Miner
ensure_wallet Trader

TRADER_CLI="$BCLI -rpcwallet=Trader"
MINER_CLI="$BCLI -rpcwallet=Miner"

#2) Fondos para el minero
MINER_ADDR=$($MINER_CLI getnewaddress "Miner coinbase")
$BCLI generatetoaddress 103 "$MINER_ADDR" >/dev/null

#3) Seleccionar dos UTXOs de (≈) 50 BTC 
UTXOS=$($MINER_CLI listunspent | \
        jq '[.[] | select(.amount>=50)] | sort_by(.confirmations) | .[0:2]')

TXID0=$(echo "$UTXOS" | jq -r '.[0].txid')
VOUT0=$(echo "$UTXOS" | jq -r '.[0].vout')
TXID1=$(echo "$UTXOS" | jq -r '.[1].txid')
VOUT1=$(echo "$UTXOS" | jq -r '.[1].vout')

TRADER_ADDR=$($TRADER_CLI getnewaddress Parent)
CHANGE_ADDR=$($MINER_CLI getnewaddress Change)

#4) Construir y transmitir la transacción Parent (RBF = true)
INPUTS=$(jq -n --arg tx0 "$TXID0" --argjson v0 "$VOUT0" \
                 --arg tx1 "$TXID1" --argjson v1 "$VOUT1" \
                 '[{txid:$tx0,vout:$v0},{txid:$tx1,vout:$v1}]')

OUTPUTS=$(jq -n --arg to "$TRADER_ADDR" --arg ch "$CHANGE_ADDR" \
                '{($to):70, ($ch):29.99999}')

RAW_PARENT=$($BCLI createrawtransaction "$INPUTS" "$OUTPUTS" 0 true) # El flag true activa RBF.
SIGNED_PARENT=$($MINER_CLI signrawtransactionwithwallet "$RAW_PARENT" | jq -r .hex)
PARENT_TXID=$($BCLI sendrawtransaction "$SIGNED_PARENT")

echo -e "\n🟢 Parent TXID: $PARENT_TXID"

#5) JSON con detalles de la Parent
ENTRY=$($BCLI getmempoolentry "$PARENT_TXID")
JSON_PARENT=$(jq -n \
  --argjson inp "$INPUTS" \
  --argjson out "$(echo "$OUTPUTS" | jq '[to_entries[] | {script_pubkey:.key, amount:.value}]')" \
  --argjson fee "$(echo "$ENTRY" | jq .fees.base)" \
  --argjson wgt "$(echo "$ENTRY" | jq .weight)" \
  '{input:$inp, output:$out, Fees:$fee, Weight:$wgt}')

echo -e "\n📦 Parent JSON:"
echo "$JSON_PARENT" | jq .

#6) Construir y transmitir el Child (CPFP)
CHILD_ADDR=$($MINER_CLI getnewaddress Miner_2)

CHILD_IN=$(jq -n --arg id "$PARENT_TXID" '[{txid:$id,vout:1}]')
CHILD_OUT=$(jq -n --arg a "$CHILD_ADDR" '{($a):29.99998}')

RAW_CHILD=$($BCLI createrawtransaction "$CHILD_IN" "$CHILD_OUT" 0 true)
SIGNED_CHILD=$($MINER_CLI signrawtransactionwithwallet "$RAW_CHILD" | jq -r .hex)
CHILD_TXID=$($BCLI sendrawtransaction "$SIGNED_CHILD")

echo -e "\n🟡 Child TXID:  $CHILD_TXID"
$BCLI getmempoolentry "$CHILD_TXID" | jq .

#7) RBF +10 000 sat sobre la Parent
OUTPUTS_BUMP=$(jq -n --arg to "$TRADER_ADDR" --arg ch "$CHANGE_ADDR" \
                     '{($to):70, ($ch):29.99989}')

RAW_RBF=$($BCLI createrawtransaction "$INPUTS" "$OUTPUTS_BUMP" 0 true)
SIGNED_RBF=$($MINER_CLI signrawtransactionwithwallet "$RAW_RBF" | jq -r .hex)
NEW_PARENT_TXID=$($BCLI sendrawtransaction "$SIGNED_RBF")

echo -e "\n🔄 Nueva Parent (RBF) TXID: $NEW_PARENT_TXID"

#8) Segundo intento de consultar el Child
echo -e "\n🔍 Intentando consultar nuevamente el Child tras el RBF:"
$BCLI getmempoolentry "$CHILD_TXID" 2>&1 || true

#9) Explicación de lo sucedido
cat <<EOF

➡️  Al retransmitir la Parent con RBF, el txid original quedó fuera del mempool.
    El Child dependía de ese txid (lo refería como input). Al volverse inválido
    su input, el nodo elimina la transacción hija, por eso ya no aparece en
    el mempool.

EOF

#10) Estado final del mempool (solo la nueva Parent)
echo "🗂️  Mempool final:"
$BCLI getrawmempool | jq .
