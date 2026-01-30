#!/usr/bin/env bash
# Ejercicio Time‑Lock + OP_RETURN en Bitcoin regtest
set -euo pipefail

MINER="Miner"
EMPLEADO="Empleado"
EMPLEADOR="Empleador"
BCLI="bitcoin-cli -regtest"

# Función auxiliar: convierte texto UTF‑8 → hex (sin usar xxd)
to_hex() {
  # Uso: to_hex "Mensaje"
  echo -n "$1" | od -An -t x1 | tr -d ' \n'
}

# 1. Crear / cargar wallets y fondear al miner
echo -e "\n➡️  Creando (o cargando) wallets…"
for wallet in "$MINER" "$EMPLEADO" "$EMPLEADOR"; do
  $BCLI createwallet "$wallet"  > /dev/null 2>&1 \
  || $BCLI loadwallet   "$wallet" > /dev/null
done

MINER_ADDR=$($BCLI -rpcwallet="$MINER" getnewaddress "Recompensa de Minado")
$BCLI generatetoaddress 103 "$MINER_ADDR" > /dev/null   # dos recompensas maduras

EMPLEADOR_ADDR=$($BCLI -rpcwallet="$EMPLEADOR" getnewaddress "Fondos Empresa")
$BCLI -rpcwallet="$MINER" sendtoaddress "$EMPLEADOR_ADDR" 50 > /dev/null
$BCLI generatetoaddress 1 "$MINER_ADDR"  > /dev/null    # confirma el envío
echo "✅ Empleador fondeado con 50 BTC"

# 2. Construir y firmar la transacción con nLockTime = 500
echo -e "\n➡️  Creando transacción de salario con timelock…"
EMPLEADOR_UTXO=$($BCLI -rpcwallet="$EMPLEADOR" listunspent | jq '.[0]')
INPUTS=$(echo "$EMPLEADOR_UTXO" | jq -c '[{txid:.txid, vout:.vout}]')

UTXO_VALUE=$(echo "$EMPLEADOR_UTXO" | jq -r '.amount')
PAGO=40
FEE=0.0001
CHANGE=$(awk "BEGIN {printf \"%.8f\", $UTXO_VALUE - $PAGO - $FEE}")

EMPLEADO_ADDR=$($BCLI -rpcwallet="$EMPLEADO" getnewaddress "Salario")
EMPLEADOR_CHANGE=$($BCLI -rpcwallet="$EMPLEADOR" getrawchangeaddress)

OUTPUTS=$(jq -n \
  --arg emp "$EMPLEADO_ADDR" \
  --arg chg "$EMPLEADOR_CHANGE" \
  --argjson pago "$PAGO" \
  --argjson chgamt "$CHANGE" \
  '{($emp):$pago, ($chg):$chgamt}')

LOCKTIME=500
RAW_TX=$($BCLI createrawtransaction "$INPUTS" "$OUTPUTS" "$LOCKTIME")
SIGNED_TX=$($BCLI -rpcwallet="$EMPLEADOR" signrawtransactionwithwallet "$RAW_TX" \
           | jq -r '.hex')

# 3. Intentar transmitir antes de tiempo (debe fallar)
echo -e "\n➡️  Intentando transmitir antes del bloque 500 (debe fallar)…"
if ! $BCLI sendrawtransaction "$SIGNED_TX" 2>/dev/null; then
  echo "👌 Rechazada como non‑final (nLockTime 500 aún no cumplido)"
fi

# 4. Minar hasta altura 500 y retransmitir
CURRENT=$($BCLI getblockcount)
NEEDED=$((LOCKTIME - CURRENT))
[[ $NEEDED -gt 0 ]] && \
  $BCLI generatetoaddress "$NEEDED" "$MINER_ADDR" > /dev/null

TXID_SALARIO=$($BCLI sendrawtransaction "$SIGNED_TX")
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null     # confirmación

echo -e "\nSaldos tras pagar el salario:"
echo "  Empleador : $($BCLI -rpcwallet="$EMPLEADOR" getbalance) BTC"
echo "  Empleado  : $($BCLI -rpcwallet="$EMPLEADO"  getbalance) BTC"

# 5. Empleado gasta el output (OP_RETURN + 39.999 BTC)
echo -e "\n➡️  Empleado gasta su salario con un OP_RETURN…"
MSG="He recibido mi salario, ahora soy rico"
HEX_MSG=$(to_hex "$MSG")

DEST_ADDR=$($BCLI -rpcwallet="$EMPLEADO" getnewaddress "Gasto personal")

PSBT=$($BCLI -rpcwallet="$EMPLEADO" walletcreatefundedpsbt \
      "[]" \
      "[{\"data\":\"$HEX_MSG\"}, {\"$DEST_ADDR\":39.999}]" \
      0 \
      "{\"subtractFeeFromOutputs\":[1]}" | jq -r '.psbt')

SIGNED_PSBT=$($BCLI -rpcwallet="$EMPLEADO" walletprocesspsbt "$PSBT" | jq -r '.psbt')
FINAL_TX=$($BCLI finalizepsbt "$SIGNED_PSBT" | jq -r '.hex')
TXID_GASTO=$($BCLI sendrawtransaction "$FINAL_TX")
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null      # confirmación

echo -e "\n🎉 Transacción con OP_RETURN transmitida: $TXID_GASTO"

echo -e "\nSaldos finales:"
echo "  Empleador : $($BCLI -rpcwallet="$EMPLEADOR" getbalance) BTC"
echo "  Empleado  : $($BCLI -rpcwallet="$EMPLEADO"  getbalance) BTC"
echo -e "\n✅ Fin del ejercicio Time‑Lock + OP_RETURN en Bitcoin regtest"
