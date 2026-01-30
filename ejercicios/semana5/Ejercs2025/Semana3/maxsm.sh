#!/usr/bin/env bash
# Ejemplo completo de creación y uso de una wallet multisig 2-de-2 en regtest.
# Steps: crear wallets, minar fondos, configurar la multisig, fondearla
# y finalmente gastar desde ella usando PSBT.

set -euo pipefail

# Alias para bitcoin-cli apuntando a regtest
BCLI="bitcoin-cli -regtest"

########################################
# 1. Crear las wallets básicas
########################################
echo "📌 Creando wallets..."
for wallet in Miner Alice Bob; do
  # Crea tres wallets con claves privadas normales
  $BCLI createwallet "$wallet" >/dev/null
done
# Crea la wallet “Multisig” sin claves privadas y vacía
$BCLI -named createwallet wallet_name="Multisig" disable_private_keys=true blank=true >/dev/null

########################################
# 2. Minar bloques para obtener saldo inicial
########################################
echo "⛏️ Minando bloques y fondeando Miner..."
MINER_ADDR=$($BCLI -rpcwallet=Miner getnewaddress "Recompensa")  # Dirección coinbase
$BCLI generatetoaddress 103 "$MINER_ADDR" >/dev/null              # 103 bloques = 3 coinbase maduras

########################################
# 3. Transferir 50 BTC a Alice y 50 BTC a Bob
########################################
echo "💰 Enviando 50 BTC a Alice y Bob..."
ALICE_ADDR=$($BCLI -rpcwallet=Alice getnewaddress "Fondos Alice")
BOB_ADDR=$($BCLI -rpcwallet=Bob getnewaddress "Fondos Bob")
$BCLI -rpcwallet=Miner sendmany "" "{\"$ALICE_ADDR\":50,\"$BOB_ADDR\":50}" >/dev/null
$BCLI generatetoaddress 1 "$MINER_ADDR" >/dev/null   # Confirma la tx
echo "✅ Alice y Bob fondeados con 50 BTC cada uno."
echo "------------------------------------------------"

########################################
# 4. Construir la wallet Multisig 2-de-2 (wsh(multi(2,xpubA,xpubB)))
########################################
echo "🔑 Creando wallet Multisig 2-de-2 con claves extendidas (xpub)..."
# Extrae los xpub externos (/0/*) e internos (/1/*) de Alice y Bob
EXT_XPUB_ALICE=$($BCLI -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')
EXT_XPUB_BOB=$($BCLI  -rpcwallet=Bob   listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')
INT_XPUB_ALICE=$($BCLI -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')
INT_XPUB_BOB=$($BCLI  -rpcwallet=Bob   listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')

# Descriptores sumarios para cuentas externa (recepción) e interna (cambio)
EXT_DESC_SUM=$($BCLI getdescriptorinfo "wsh(multi(2,$EXT_XPUB_ALICE,$EXT_XPUB_BOB))" | jq -r '.descriptor')
INT_DESC_SUM=$($BCLI getdescriptorinfo "wsh(multi(2,$INT_XPUB_ALICE,$INT_XPUB_BOB))" | jq -r '.descriptor')

# Importa ambos descriptores y los activa
MULTI_DESC=$(jq -n "[\
  {\"desc\":\"$EXT_DESC_SUM\",\"active\":true,\"internal\":false,\"timestamp\":\"now\"},\
  {\"desc\":\"$INT_DESC_SUM\",\"active\":true,\"internal\":true,\"timestamp\":\"now\"}\
]")
$BCLI -rpcwallet=Multisig importdescriptors "$MULTI_DESC" >/dev/null

MULTI_ADDR=$($BCLI -rpcwallet=Multisig getnewaddress)  # Primera dirección multisig
echo "✅ Dirección multisig creada: $MULTI_ADDR"
echo "------------------------------------------------"

########################################
# 5. Fondear la multisig con 20 BTC (10 de Alice y 10 de Bob)
########################################
echo "📨 Creando PSBT para fondear Multisig con 20 BTC (10 Alice, 10 Bob)..."
ALICE_UTXO=$($BCLI -rpcwallet=Alice listunspent | jq '.[0]')       # Primer UTXO de Alice
BOB_UTXO=$($BCLI  -rpcwallet=Bob   listunspent | jq '.[0]')       # Primer UTXO de Bob
ALICE_CHANGE=$($BCLI -rpcwallet=Alice getrawchangeaddress)        # Cambio Alice
BOB_CHANGE=$($BCLI  -rpcwallet=Bob   getrawchangeaddress)         # Cambio Bob

INPUTS=$(jq -n "[\
 {\"txid\":\"$(jq -r '.txid' <<<"$ALICE_UTXO")\",\"vout\":$(jq -r '.vout' <<<"$ALICE_UTXO")},\
 {\"txid\":\"$(jq -r '.txid' <<<"$BOB_UTXO")\",\"vout\":$(jq -r '.vout' <<<"$BOB_UTXO")}\
]")
OUTPUTS=$(jq -n "{\"$MULTI_ADDR\":20,\"$ALICE_CHANGE\":39.9999,\"$BOB_CHANGE\":39.9999}")

# Crear PSBT y firmar con ambos
PSBT=$($BCLI createpsbt "$INPUTS" "$OUTPUTS")
PSBT=$($BCLI -rpcwallet=Alice walletprocesspsbt "$PSBT" | jq -r '.psbt')
PSBT=$($BCLI -rpcwallet=Bob   walletprocesspsbt "$PSBT" | jq -r '.psbt')

HEXTX=$($BCLI finalizepsbt "$PSBT" | jq -r '.hex')  # Se finaliza la PSBT
TXID=$($BCLI sendrawtransaction "$HEXTX")           # Se transmite
$BCLI generatetoaddress 1 "$MINER_ADDR" >/dev/null  # Se confirma
echo "✅ Multisig fondeada con éxito en TXID: $TXID"
echo "------------------------------------------------"

########################################
# 6. Gastar 3 BTC desde la multisig hacia una nueva dirección de Alice
########################################
echo "💸 Creando PSBT para gastar 3 BTC desde Multisig hacia Alice..."
MULTI_UTXO=$($BCLI -rpcwallet=Multisig listunspent | jq '.[0]')  # UTXO a gastar

# Deriva una dirección interna nueva para el cambio de la multisig
MULTI_CHANGE_DESC=$($BCLI -rpcwallet=Multisig listdescriptors | jq -r '.descriptors[] | select(.internal==true).desc')
MULTI_CHANGE_IDX=$($BCLI  -rpcwallet=Multisig listdescriptors | jq -r '.descriptors[] | select(.internal==true).next_index')
MULTI_CHANGE_ADDR=$($BCLI deriveaddresses "$MULTI_CHANGE_DESC" "[$MULTI_CHANGE_IDX,$MULTI_CHANGE_IDX]" | jq -r '.[0]')

ALICE_NEW_ADDR=$($BCLI -rpcwallet=Alice getnewaddress "Desde Multisig")  # Destino de los 3 BTC

# Crea PSBT autofondeada (walletcreatefundedpsbt)
SPEND_PSBT=$($BCLI -rpcwallet=Multisig walletcreatefundedpsbt \
"[{\"txid\":\"$(jq -r '.txid' <<<"$MULTI_UTXO")\",\"vout\":$(jq -r '.vout' <<<"$MULTI_UTXO")}]" \
"{\"$ALICE_NEW_ADDR\":3,\"$MULTI_CHANGE_ADDR\":16.9999}" \
0 '{"includeWatching":true}' | jq -r '.psbt')

# Firmas de Alice y Bob
SPEND_PSBT=$($BCLI -rpcwallet=Alice walletprocesspsbt "$SPEND_PSBT" | jq -r '.psbt')
SPEND_PSBT=$($BCLI -rpcwallet=Bob   walletprocesspsbt "$SPEND_PSBT" | jq -r '.psbt')

SPEND_HEX=$($BCLI finalizepsbt "$SPEND_PSBT" | jq -r '.hex')
SPEND_TXID=$($BCLI sendrawtransaction "$SPEND_HEX")
$BCLI generatetoaddress 1 "$MINER_ADDR" >/dev/null  # Confirma la salida
echo "✅ 3 BTC enviados a Alice desde Multisig: $SPEND_TXID"
echo "------------------------------------------------"

########################################
# 7. Mostrar los saldos finales
########################################
echo "🏁 Saldos finales:"
echo "Miner    : $($BCLI -rpcwallet=Miner getbalance) BTC"
echo "Alice    : $($BCLI -rpcwallet=Alice getbalance) BTC"
echo "Bob      : $($BCLI -rpcwallet=Bob getbalance) BTC"
echo "Multisig : $($BCLI -rpcwallet=Multisig getbalances | jq -r '.mine.trusted') BTC"
echo "⚡ Ejercicio completado 🎉"