#!/bin/bash
# Autor: 0xlaga
# Semana 3 - Multisig 2-de-2: Setup y Liquidación en regtest

set -e

BCLI="bitcoin-cli -regtest"

###############################################################################
# PARTE 1 – CONFIGURAR MULTISIG
###############################################################################

# 1. Crear tres wallets: Miner, Alice, Bob
echo "=== 1. Creando wallets ==="
for W in Miner Alice Bob; do
  $BCLI createwallet "$W" 2>/dev/null || $BCLI loadwallet "$W" 2>/dev/null || true
done

# 2. Fondear wallets
echo "=== 2. Fondeando wallets ==="
MINER_ADDR=$($BCLI -rpcwallet=Miner getnewaddress "Recompensa")
$BCLI generatetoaddress 101 "$MINER_ADDR" > /dev/null

ALICE_ADDR=$($BCLI -rpcwallet=Alice getnewaddress "Fondeo")
BOB_ADDR=$($BCLI -rpcwallet=Bob getnewaddress "Fondeo")

$BCLI -rpcwallet=Miner sendtoaddress "$ALICE_ADDR" 15 > /dev/null
$BCLI -rpcwallet=Miner sendtoaddress "$BOB_ADDR" 15 > /dev/null
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

echo "Alice: $($BCLI -rpcwallet=Alice getbalance) BTC"
echo "Bob:   $($BCLI -rpcwallet=Bob getbalance) BTC"

# 3. Crear wallet Multisig 2-de-2 con descriptors
echo "=== 3. Creando wallet Multisig 2-de-2 ==="

# Extraer xpubs de Alice y Bob (external /0/* e internal /1/*)
ALICE_XPUB_EXT=$($BCLI -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh") and contains("/0/*")) | .desc' | sed 's/^wpkh(\(.*\))#.*/\1/')
ALICE_XPUB_INT=$($BCLI -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh") and contains("/1/*")) | .desc' | sed 's/^wpkh(\(.*\))#.*/\1/')
BOB_XPUB_EXT=$($BCLI -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh") and contains("/0/*")) | .desc' | sed 's/^wpkh(\(.*\))#.*/\1/')
BOB_XPUB_INT=$($BCLI -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc | startswith("wpkh") and contains("/1/*")) | .desc' | sed 's/^wpkh(\(.*\))#.*/\1/')

# Construir descriptors multisig con checksum
DESC_EXT=$($BCLI getdescriptorinfo "wsh(multi(2,$ALICE_XPUB_EXT,$BOB_XPUB_EXT))" | jq -r '.descriptor')
DESC_INT=$($BCLI getdescriptorinfo "wsh(multi(2,$ALICE_XPUB_INT,$BOB_XPUB_INT))" | jq -r '.descriptor')

# Crear wallet watch-only e importar descriptors
$BCLI -named createwallet wallet_name="Multisig" disable_private_keys=true blank=true
$BCLI -rpcwallet=Multisig importdescriptors "$(jq -n \
  --arg ext "$DESC_EXT" --arg int "$DESC_INT" \
  '[{"desc":$ext,"active":true,"internal":false,"timestamp":"now"},
    {"desc":$int,"active":true,"internal":true,"timestamp":"now"}]')"

MULTISIG_ADDR=$($BCLI -rpcwallet=Multisig getnewaddress)
echo "Dirección Multisig: $MULTISIG_ADDR"

# 4. Crear PSBT para financiar multisig con 20 BTC (10 de cada uno)
echo "=== 4. Financiando multisig con PSBT ==="

ALICE_UTXO=$($BCLI -rpcwallet=Alice listunspent | jq '.[0]')
BOB_UTXO=$($BCLI -rpcwallet=Bob listunspent | jq '.[0]')

INPUTS=$(jq -n \
  --arg at "$(echo $ALICE_UTXO | jq -r '.txid')" --argjson av "$(echo $ALICE_UTXO | jq '.vout')" \
  --arg bt "$(echo $BOB_UTXO | jq -r '.txid')"   --argjson bv "$(echo $BOB_UTXO | jq '.vout')" \
  '[{"txid":$at,"vout":$av},{"txid":$bt,"vout":$bv}]')

ALICE_CHANGE_ADDR=$($BCLI -rpcwallet=Alice getrawchangeaddress)
BOB_CHANGE_ADDR=$($BCLI -rpcwallet=Bob getrawchangeaddress)

OUTPUTS=$(jq -n \
  --arg ms "$MULTISIG_ADDR" \
  --arg ac "$ALICE_CHANGE_ADDR" \
  --arg bc "$BOB_CHANGE_ADDR" \
  '[{($ms):20},{($ac):4.9999},{($bc):4.9999}]')

PSBT=$($BCLI createpsbt "$INPUTS" "$OUTPUTS")

# Firmar con Alice, luego con Bob
PSBT=$($BCLI -rpcwallet=Alice walletprocesspsbt "$PSBT" | jq -r '.psbt')
PSBT=$($BCLI -rpcwallet=Bob walletprocesspsbt "$PSBT" | jq -r '.psbt')

# Finalizar y transmitir
HEX=$($BCLI finalizepsbt "$PSBT" | jq -r '.hex')
TXID=$($BCLI sendrawtransaction "$HEX")
echo "Tx de financiamiento: $TXID"

# 5. Confirmar con bloques adicionales
echo "=== 5. Confirmando ==="
$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# 6. Saldos tras financiamiento
echo "=== 6. Saldos después del financiamiento ==="
echo "Alice:    $($BCLI -rpcwallet=Alice getbalance) BTC"
echo "Bob:      $($BCLI -rpcwallet=Bob getbalance) BTC"
echo "Multisig: $($BCLI -rpcwallet=Multisig getbalance) BTC"

###############################################################################
# PARTE 2 – LIQUIDAR MULTISIG
###############################################################################

echo ""
echo "============================================="
echo "         LIQUIDAR MULTISIG"
echo "============================================="

# 1. Crear PSBT para gastar desde Multisig – enviar 3 BTC a Alice
echo "=== 1. Creando PSBT de gasto ==="
ALICE_RECV=$($BCLI -rpcwallet=Alice getnewaddress "Desde_Multisig")

SPEND_PSBT=$($BCLI -rpcwallet=Multisig walletcreatefundedpsbt '[]' "[{\"$ALICE_RECV\":3}]" 0 '{"includeWatching":true}' | jq -r '.psbt')

# 2. Firmar con Alice
echo "=== 2. Alice firma ==="
SPEND_PSBT=$($BCLI -rpcwallet=Alice walletprocesspsbt "$SPEND_PSBT" | jq -r '.psbt')

# 3. Firmar con Bob
echo "=== 3. Bob firma ==="
SPEND_PSBT=$($BCLI -rpcwallet=Bob walletprocesspsbt "$SPEND_PSBT" | jq -r '.psbt')

# 4. Extraer y transmitir
echo "=== 4. Finalizando y transmitiendo ==="
SPEND_HEX=$($BCLI finalizepsbt "$SPEND_PSBT" | jq -r '.hex')
SPEND_TXID=$($BCLI sendrawtransaction "$SPEND_HEX")
echo "Tx de liquidación: $SPEND_TXID"

$BCLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# 5. Saldos finales
echo "=== 5. Saldos finales ==="
echo "Alice:    $($BCLI -rpcwallet=Alice getbalance) BTC"
echo "Bob:      $($BCLI -rpcwallet=Bob getbalance) BTC"
echo "Multisig: $($BCLI -rpcwallet=Multisig getbalance) BTC"

echo ""
echo "✅ Ejercicio Semana 3 completado."
