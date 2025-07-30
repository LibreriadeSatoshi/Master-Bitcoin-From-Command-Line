#!/usr/bin/env bash
set -euo pipefail


BCLI="bitcoin-cli -regtest"
MCLI="$BCLI -rpcwallet=Miner"
ACLI="$BCLI -rpcwallet=Alice"

# ── Params
TIMELOCK=10        # bloques que exige nSequence
ALICE_FUND=20      # BTC que recibe Alice de inicio
PAYBACK=10         # BTC que Alice devuelve al Miner
FEE_RATE=0.00002   # ~20 sat/vB — tarifa fija
EPS=0.00000001     # tolerancia para comparar montos

# ── Utilidades básicas
ensure(){  # crea-o-carga wallet si hace falta
  $BCLI -rpcwallet="$1" getwalletinfo >/dev/null 2>&1 || \
  $BCLI loadwallet "$1"   >/dev/null 2>&1 || \
  $BCLI createwallet "$1" >/dev/null
}
bal(){      # saldo con 8 decimales
  $BCLI -rpcwallet="$1" getbalance | awk '{printf "%.8f",$0}'
}

### 1) Preparar fondos: 101 bloques + 20 BTC a Alice (idempotente)
prep_funds(){
  ensure Miner; ensure Alice

  # minar 101 bloques si aún no existen → madura la coinbase inicial
  (( $($BCLI getblockcount) < 101 )) && \
      $BCLI generatetoaddress 101 "$($MCLI getnewaddress cb)" >/dev/null

  # ¿Alice ya tiene un UTXO exacto de 20 BTC?
  $ACLI listunspent | jq -e --argjson t $ALICE_FUND --argjson e $EPS \
     'map(select((.amount-$t)|abs<$e))|any' >/dev/null || {
       echo "[SEND] +$ALICE_FUND BTC → Alice"
       $MCLI sendtoaddress "$($ACLI getnewaddress fund)" $ALICE_FUND >/dev/null
       $BCLI generatetoaddress 1 "$($MCLI getnewaddress tmp)" >/dev/null  # confirma
     }
  echo "[INFO] Balance Alice: $(bal Alice) BTC"
}

### 2) Construir y firmar la TX timelock (versión 2, nSeq = 10)
build_tx(){
  # localizar el UTXO de 20 BTC de Alice
  UTXO=$($ACLI listunspent | jq -e \
        --argjson t $ALICE_FUND --argjson e $EPS \
        'map(select((.amount-$t)|abs<$e))|sort_by(.confirmations)[0]') \
        || { echo "❌ UTXO no encontrado"; exit 1; }

  TXID=$(jq -r .txid  <<<"$UTXO")
  VOUT=$(jq -r .vout  <<<"$UTXO")

  # input con sequence = 10  (timelock relativo)
  IN=$(jq -nc --arg tx $TXID --argjson v $VOUT --argjson s $TIMELOCK \
              '[{txid:$tx,vout:$v,sequence:$s}]')
  # salida: 10 BTC al Miner
  OUT=$(jq -nc --arg a "$($MCLI getnewaddress payback)" \
               --argjson p $PAYBACK '{($a):$p}')

  RAW1=$($BCLI createrawtransaction "$IN" "$OUT")   # tx versión 1…
  RAW2="02${RAW1:2:6}${RAW1:8}"                     # …parchada a versión 2

  # fundea la tx sin añadir nuevos inputs; la fee se resta del único output
  FUND_JSON=$($ACLI fundrawtransaction "$RAW2" \
       '{"add_inputs":false,"feeRate":'"$FEE_RATE"',"subtractFeeFromOutputs":[0],"replaceable":false}')

  HEX=$(echo "$FUND_JSON" | jq -r .hex)
  [[ "$HEX" == null ]] && { echo "❌ Fee > output"; exit 1; }

  # Core sobre-escribe nSequence ⇒ re-parchamos los últimos 4 bytes a 0a000000
  HEX_FIXED="${HEX:0:-8}0a000000"

  SIG=$($ACLI signrawtransactionwithwallet "$HEX_FIXED" | jq -r .hex)
  export TX_HEX=$SIG
  export TX_ID=$($BCLI decoderawtransaction "$SIG" | jq -r .txid)
  echo "[BUILD] TX $TX_ID lista (v2, nSeq=10)."
}

### 3) Intento prematuro — debe ser rechazado (BIP-68)
try_early(){
  echo "[TEST] Prematuro…"
  if (set +o pipefail; $BCLI sendrawtransaction "$TX_HEX" 2>&1 \
        | grep -q non-BIP68-final); then
    echo "✅ Rechazo prematuro correcto."
  else
    echo "❌ La mempool aceptó la TX — revisa script."
  fi
}

### 4) Cumplir timelock, difundir y confirmar
confirm_tx(){
  echo "[MINA] +$TIMELOCK bloques…"
  $BCLI generatetoaddress $TIMELOCK "$($MCLI getnewaddress mine)" >/dev/null
  $BCLI sendrawtransaction "$TX_HEX" >/dev/null || true      # difunde
  $BCLI generatetoaddress 1 "$($MCLI getnewaddress mine)"  >/dev/null # confirma
  echo "[DONE] TX $TX_ID confirmada."
  echo "[RES] Balance final Alice: $(bal Alice) BTC"
}

### Ejecución secuencial
prep_funds
build_tx
try_early
confirm_tx
