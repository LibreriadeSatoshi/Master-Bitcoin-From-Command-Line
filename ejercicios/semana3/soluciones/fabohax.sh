#!/bin/bash
set -euo pipefail

BITCOIN_CLI="bitcoin-cli -regtest"
DATA_DIR="$HOME/.bitcoin"

echo "> Iniciando entorno regtest con bitcoind..."
$BITCOIN_CLI stop 2>/dev/null || true
sleep 1
bitcoind -regtest -daemon

# Esperar hasta que el nodo esté listo
echo "> Esperando que bitcoind esté listo..."
until $BITCOIN_CLI getblockchaininfo > /dev/null 2>&1; do
    sleep 1
done

# === Manejar wallet Miner: borrar si existe y crear nueva con descriptors ===
echo "> Verificando wallet Miner..."
if $BITCOIN_CLI -rpcwallet=Miner getwalletinfo &>/dev/null; then
  echo "> Wallet Miner existe, borrando..."
  $BITCOIN_CLI unloadwallet Miner
  rm -rf "$DATA_DIR/regtest/wallets/Miner"
  echo "> Wallet Miner borrada."
fi
echo "> Creando wallet Miner con descriptors..."
$BITCOIN_CLI -named createwallet wallet_name=Miner descriptors=true load_on_startup=true

# === Crear wallets Alice, Bob, Multisig si no existen ===
for w in Alice Bob Multisig; do
  if $BITCOIN_CLI -rpcwallet="$w" getwalletinfo &>/dev/null; then
    echo "> Wallet '$w' ya existe. Omitiendo creación."
  else
    echo "> Creando wallet '$w'..."
    $BITCOIN_CLI -named createwallet wallet_name=$w descriptors=true load_on_startup=true
  fi
done

# Obtener dirección para minar bloques
ADDR_MINER=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress)

echo "> Minando hasta que Miner tenga al menos 101 BTC disponibles..."
SALDO=0
while (( $(echo "$SALDO < 101" | bc -l) )); do
  $BITCOIN_CLI generatetoaddress 10 "$ADDR_MINER" > /dev/null
  SALDO=$($BITCOIN_CLI -rpcwallet=Miner getbalance)
  echo "  > Saldo actual: $SALDO BTC"
done

# === Enviar 10 BTC a Alice y Bob ===
echo "> Enviando 10 BTC a Alice y Bob..."
ADDR_ALICE=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress)
ADDR_BOB=$($BITCOIN_CLI -rpcwallet=Bob getnewaddress)
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$ADDR_ALICE" 10
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$ADDR_BOB" 10
$BITCOIN_CLI generatetoaddress 1 "$ADDR_MINER"

# === Obtener descriptors limpios (sin checksum) para multisig ===
echo "> Obteniendo descriptors para multisig..."

DESC_ALICE_RAW=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress | xargs -I{} $BITCOIN_CLI -rpcwallet=Alice getaddressinfo {} | jq -r .desc)
DESC_ALICE_CLEAN=$(echo "$DESC_ALICE_RAW" | cut -d'#' -f1)
DESC_ALICE=$($BITCOIN_CLI getdescriptorinfo "$DESC_ALICE_CLEAN" | jq -r .descriptor)

DESC_BOB_RAW=$($BITCOIN_CLI -rpcwallet=Bob getnewaddress | xargs -I{} $BITCOIN_CLI -rpcwallet=Bob getaddressinfo {} | jq -r .desc)
DESC_BOB_CLEAN=$(echo "$DESC_BOB_RAW" | cut -d'#' -f1)
DESC_BOB=$($BITCOIN_CLI getdescriptorinfo "$DESC_BOB_CLEAN" | jq -r .descriptor)

DESC_MULTI="wsh(multi(2,$DESC_ALICE,$DESC_BOB))"
WRAPPED_DESC=$($BITCOIN_CLI getdescriptorinfo "$DESC_MULTI" | jq -r .descriptor)

# === Importar descriptor al wallet Multisig ===
echo "> Importando descriptor al wallet Multisig..."
$BITCOIN_CLI -rpcwallet=Multisig importdescriptors "[{\"desc\":\"$WRAPPED_DESC\",\"active\":true,\"timestamp\":\"now\"}]"

ADDR_MULTI=$($BITCOIN_CLI -rpcwallet=Multisig getnewaddress)

# === Crear PSBT para enviar 10 BTC desde Alice y 10 BTC desde Bob al multisig ===
echo "> Creando PSBT para enviar 10 BTC desde Alice y 10 BTC desde Bob al multisig..."

UTXO_ALICE=$($BITCOIN_CLI -rpcwallet=Alice listunspent | jq -r '.[0]')
TXID_ALICE=$(echo "$UTXO_ALICE" | jq -r .txid)
VOUT_ALICE=$(echo "$UTXO_ALICE" | jq -r .vout)
AMOUNT_ALICE=$(echo "$UTXO_ALICE" | jq -r .amount)

UTXO_BOB=$($BITCOIN_CLI -rpcwallet=Bob listunspent | jq -r '.[0]')
TXID_BOB=$(echo "$UTXO_BOB" | jq -r .txid)
VOUT_BOB=$(echo "$UTXO_BOB" | jq -r .vout)
AMOUNT_BOB=$(echo "$UTXO_BOB" | jq -r .amount)

CHANGE_ALICE=$(echo "$AMOUNT_ALICE - 10" | bc)
CHANGE_BOB=$(echo "$AMOUNT_BOB - 10" | bc)

PSBT=$($BITCOIN_CLI createpsbt "[{\"txid\":\"$TXID_ALICE\",\"vout\":$VOUT_ALICE},{\"txid\":\"$TXID_BOB\",\"vout\":$VOUT_BOB}]" "[{\"address\":\"$ADDR_MULTI\",\"amount\":20},{\"address\":\"$ADDR_ALICE\",\"amount\":$CHANGE_ALICE},{\"address\":\"$ADDR_BOB\",\"amount\":$CHANGE_BOB}]" 0)

# === Firmar y enviar ===
PSBT1=$($BITCOIN_CLI -rpcwallet=Alice walletprocesspsbt "$PSBT" | jq -r .psbt)
PSBT2=$($BITCOIN_CLI -rpcwallet=Bob walletprocesspsbt "$PSBT1" | jq -r .psbt)
FINAL_TX=$($BITCOIN_CLI finalizepsbt "$PSBT2" | jq -r .hex)

echo "> Enviando transacción a la red..."
TXID_FINAL=$($BITCOIN_CLI sendrawtransaction "$FINAL_TX")
$BITCOIN_CLI generatetoaddress 1 "$ADDR_MINER"

# === Saldos actuales ===
echo "> Saldos luego del fondeo multisig:"
echo "Alice:"
$BITCOIN_CLI -rpcwallet=Alice getbalance
echo "Bob:"
$BITCOIN_CLI -rpcwallet=Bob getbalance

# === Gastar desde el multisig ===
echo "> Gastando 3 BTC desde multisig a Alice..."
ADDR_ALICE_NEW=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress)
ADDR_CHANGE_MULTI=$($BITCOIN_CLI -rpcwallet=Multisig getrawchangeaddress)

UTXO_MULTI=$($BITCOIN_CLI -rpcwallet=Multisig listunspent | jq -r '.[0]')
TXID_MULTI=$(echo "$UTXO_MULTI" | jq -r .txid)
VOUT_MULTI=$(echo "$UTXO_MULTI" | jq -r .vout)
AMOUNT_MULTI=$(echo "$UTXO_MULTI" | jq -r .amount)
CHANGE_MULTI=$(echo "$AMOUNT_MULTI - 3" | bc)

PSBT_SPEND=$($BITCOIN_CLI createpsbt "[{\"txid\":\"$TXID_MULTI\",\"vout\":$VOUT_MULTI}]" "[{\"address\":\"$ADDR_ALICE_NEW\",\"amount\":3},{\"address\":\"$ADDR_CHANGE_MULTI\",\"amount\":$CHANGE_MULTI}]" 0)

# Firmar con Alice y Bob
PSBT_SPEND_1=$($BITCOIN_CLI -rpcwallet=Alice walletprocesspsbt "$PSBT_SPEND" | jq -r .psbt)
PSBT_SPEND_2=$($BITCOIN_CLI -rpcwallet=Bob walletprocesspsbt "$PSBT_SPEND_1" | jq -r .psbt)
FINAL_TX_SPEND=$($BITCOIN_CLI finalizepsbt "$PSBT_SPEND_2" | jq -r .hex)

# Transmitir
TXID_SPEND=$($BITCOIN_CLI sendrawtransaction "$FINAL_TX_SPEND")
$BITCOIN_CLI generatetoaddress 1 "$ADDR_MINER"

# === Saldos finales ===
echo "> Saldos finales:"
echo "Alice:"
$BITCOIN_CLI -rpcwallet=Alice getbalance
echo "Bob:"
$BITCOIN_CLI -rpcwallet=Bob getbalance

echo "✅ Script completo ejecutado con éxito."

