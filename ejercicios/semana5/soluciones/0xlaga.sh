#!/bin/bash
# Autor: 0xlaga
# Semana 5 - Miniscript: wsh(andor(pk(Alice),older(10),pk(Bob)))
#
# Política: or(pk(Bob), and(pk(Alice), older(10)))
#   - Bob puede gastar en cualquier momento
#   - Alice puede gastar después de 10 bloques (timelock relativo)

set -e

BCLI="bitcoin-cli -regtest"

# Función auxiliar: crear PSBT, procesar con Miniscript wallet, firmar con Alice
sign_with_alice() {
  local psbt
  psbt=$($BCLI createpsbt "[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT,\"sequence\":10}]" \
    "[{\"$ALICE_RECV\":4.9999}]")
  psbt=$($BCLI -rpcwallet=Miniscript walletprocesspsbt "$psbt" | jq -r '.psbt')
  $BCLI -rpcwallet=Alice walletprocesspsbt "$psbt" | jq -r '.psbt'
}

# === PARTE 1: CONFIGURAR CONTRATO MINISCRIPT ===

echo "=== 1. Creando wallets ==="
for W in Miner Alice Bob; do
  $BCLI createwallet "$W" 2>/dev/null || $BCLI loadwallet "$W" 2>/dev/null || true
done

echo "=== 2. Fondeando Miner ==="
MINER_ADDR=$($BCLI -rpcwallet=Miner getnewaddress)
$BCLI generatetoaddress 103 "$MINER_ADDR" > /dev/null
echo "Miner: $($BCLI -rpcwallet=Miner getbalance) BTC"

echo ""
echo "=== 3. Explicación del miniscript ==="
echo "Política: or(pk(Bob), and(pk(Alice), older(10)))"
echo "  - Bob puede gastar en cualquier momento"
echo "  - Alice puede gastar solo después de 10 bloques"
echo "Compilado: wsh(andor(pk(Alice),older(10),pk(Bob)))"
echo "Ref: https://bitcoin.sipa.be/miniscript/"

echo ""
echo "=== 4. Creando descriptor miniscript ==="
get_xpub() {
  $BCLI -rpcwallet="$1" listdescriptors | jq -r \
    '.descriptors[] | select(.desc | startswith("wpkh") and contains("/0/*")) | .desc' | \
    sed 's/^wpkh(\(.*\))#.*/\1/'
}
ALICE_XPUB=$(get_xpub Alice)
BOB_XPUB=$(get_xpub Bob)

DESC_RAW="wsh(andor(pk($ALICE_XPUB),older(10),pk($BOB_XPUB)))"
DESC=$($BCLI getdescriptorinfo "$DESC_RAW" | jq -r '.descriptor')
echo "Descriptor generado."

echo "=== 5. Creando wallet Miniscript (watch-only) ==="
$BCLI -named createwallet wallet_name="Miniscript" disable_private_keys=true blank=true
$BCLI -rpcwallet=Miniscript importdescriptors \
  "$(jq -n --arg d "$DESC" '[{"desc":$d,"active":true,"timestamp":"now"}]')"

MS_ADDR=$($BCLI -rpcwallet=Miniscript getnewaddress)
echo "Dirección: $MS_ADDR"

echo "=== 6. Enviando 5 BTC al contrato ==="
FUND_TXID=$($BCLI -rpcwallet=Miner sendtoaddress "$MS_ADDR" 5)
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
echo "Tx: $FUND_TXID"
echo "Saldo Miniscript: $($BCLI -rpcwallet=Miniscript getbalance) BTC"

# === PARTE 2: GASTAR POR EL CAMINO DE ALICE (older(10)) ===

echo ""
echo "=== 7. Intentando gastar ANTES de 10 bloques ==="
ALICE_RECV=$($BCLI -rpcwallet=Alice getnewaddress)
MS_TXID=$($BCLI -rpcwallet=Miniscript listunspent | jq -r '.[0].txid')
MS_VOUT=$($BCLI -rpcwallet=Miniscript listunspent | jq '.[0].vout')

SIGNED=$(sign_with_alice)
FINAL=$($BCLI finalizepsbt "$SIGNED")

if [ "$(echo "$FINAL" | jq -r '.complete')" = "true" ]; then
  $BCLI sendrawtransaction "$(echo "$FINAL" | jq -r '.hex')" 2>&1 || true
  echo "❌ Tx rechazada: non-BIP68-final (older(10) no cumplido)"
else
  echo "❌ PSBT incompleta: older(10) no cumplido (solo 1 confirmación)"
fi

echo ""
echo "=== 8. Minando 10 bloques y gastando ==="
$BCLI generatetoaddress 10 "$MINER_ADDR" > /dev/null
echo "Bloque actual: $($BCLI getblockcount)"

SIGNED=$(sign_with_alice)
FINAL=$($BCLI finalizepsbt "$SIGNED")

if [ "$(echo "$FINAL" | jq -r '.complete')" = "true" ]; then
  SPEND_TXID=$($BCLI sendrawtransaction "$(echo "$FINAL" | jq -r '.hex')")
  echo "✅ Tx enviada: $SPEND_TXID"
  $BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
else
  echo "ERROR: No se pudo finalizar la PSBT"; exit 1
fi

echo ""
echo "=== Resultado ==="
echo "✅ Camino utilizado: and(pk(Alice), older(10))"
echo "Saldos finales:"
echo "  Alice:      $($BCLI -rpcwallet=Alice getbalance) BTC"
echo "  Bob:        $($BCLI -rpcwallet=Bob getbalance) BTC"
echo "  Miniscript: $($BCLI -rpcwallet=Miniscript getbalance) BTC"
echo ""
echo "✅ Ejercicio Semana 5 completado."
