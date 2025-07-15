#!/bin/bash

echo "Verificando dependencias necesarias..."

install_if_missing() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Instalando $1..."
    sudo apt update
    sudo apt install -y "$2"
  else
    echo "$1 ya esta instalado"
  fi
}

install_if_missing jq jq
install_if_missing bc bc

echo
echo "Iniciando Bitcoin daemon..."

if pgrep -f "bitcoind.*-regtest" >/dev/null 2>&1; then
  echo "bitcoind ya esta ejecutandose"
else
  echo "Iniciando bitcoind en regtest..."
  rm -rf "$BITCOIN_DIR/regtest"
  bitcoind -regtest -daemon
  sleep 5
fi

echo
echo "Configurando wallets..."

wallets=$(bitcoin-cli listwallets | jq -r '.[]')

for w in Miner Alice Bob; do
  if ! echo "$wallets" | grep -q "^$w$"; then
    echo "Creando wallet '$w'..."
    bitcoin-cli createwallet "$w" >/dev/null 2>&1
  else
    echo "Wallet '$w' ya existe"
  fi
done

sleep 2

echo
echo "Generando fondos iniciales..."

miner_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner Fondeo")
bitcoin-cli -rpcwallet=Miner generatetoaddress 101 "$miner_addr" >/dev/null 2>&1

bob_addr=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Bob Fondeo")
alice_addr=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Alice Fondeo")

echo "Enviando 50 BTC a Bob y Alice desde Miner..."
bitcoin-cli -rpcwallet=Miner sendtoaddress "$bob_addr" 50.0 
bitcoin-cli -rpcwallet=Miner sendtoaddress "$alice_addr" 50.0

bitcoin-cli -rpcwallet=Miner generatetoaddress 5 "$miner_addr" >/dev/null 2>&1

echo "Saldo Miner: $(bitcoin-cli -rpcwallet=Miner getbalance) BTC"
echo "Saldo Bob: $(bitcoin-cli -rpcwallet=Bob getbalance) BTC"
echo "Saldo Alice: $(bitcoin-cli -rpcwallet=Alice getbalance) BTC"

echo
echo "Configurando wallet multisig..."

wallets=$(bitcoin-cli listwallets | jq -r '.[]')

if ! echo "$wallets" | grep -q "^Multisig$"; then
  echo "Creando wallet 'Multisig'..."
  #Watch only y en blanco
  bitcoin-cli createwallet "Multisig" true true >/dev/null 2>&1
else
  echo "Wallet 'Multisig' ya existe"
fi

echo
echo "Obteniendo claves publicas extendidas..."

alice_pubkey=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors[] | select(.desc | test("^wpkh")) | select(.internal == false) | .desc | capture("wpkh\\((?<key>[^)]*)\\)").key')
bob_pubkey=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors[] | select(.desc | test("^wpkh")) | select(.internal == false) | .desc | capture("wpkh\\((?<key>[^)]*)\\)").key')

echo "Clave publica extendida Alice: $alice_pubkey"
echo "Clave publica extendida Bob: $bob_pubkey"

if [[ -z "$alice_pubkey" || -z "$bob_pubkey" ]]; then
  echo "Error: No se pudieron obtener las claves publicas extendidas"
  exit 1
fi

multisig_descriptor="wsh(multi(2,$alice_pubkey,$bob_pubkey))"

descriptor_info=$(bitcoin-cli -regtest getdescriptorinfo "$multisig_descriptor")
checksum=$(echo "$descriptor_info" | jq -r '.checksum')
multisig_descriptor_checksum="$multisig_descriptor#$checksum"

echo "Descriptor multisig: $multisig_descriptor_checksum"

# Verificar si ya esta importado
imported_descs=$(bitcoin-cli -regtest -rpcwallet=Multisig listdescriptors 2>/dev/null | jq -r '.descriptors[].desc')

desc_exists=false
for desc in $imported_descs; do
  desc_no_checksum=${desc%%#*}
  if [[ "$desc_no_checksum" == "$multisig_descriptor" ]]; then
    desc_exists=true
    break
  fi
done

if $desc_exists; then
  echo "El descriptor multisig ya esta importado"
else
  echo "Importando descriptor multisig al wallet..."
  bitcoin-cli -regtest -rpcwallet=Multisig importdescriptors "[{
    \"desc\": \"$multisig_descriptor_checksum\",
    \"active\": true,
    \"internal\": false,
    \"timestamp\": \"now\"
  }]" || { echo "Error al importar el descriptor multisig"; exit 1; }
  echo "Descriptor multisig importado exitosamente"
fi

echo
echo "Enviando fondos a multisig..."

#Derivando manualmente direcciones multisig para recibir fondos
multisig_addr=$(bitcoin-cli -regtest deriveaddresses "$multisig_descriptor_checksum" "[0,1]"  | jq -r '.[0]')
echo "Direccion multisig: $multisig_addr"

alice_change_addr=$(bitcoin-cli -regtest -rpcwallet=Alice getrawchangeaddress)
bob_change_addr=$(bitcoin-cli -regtest -rpcwallet=Bob getrawchangeaddress)

fee=0.0005
amount_required=10

alice_utxo=$(bitcoin-cli -regtest -rpcwallet=Alice listunspent | jq -c 'map(select(.amount >= 10)) | .[0]')
bob_utxo=$(bitcoin-cli -regtest -rpcwallet=Bob listunspent | jq -c 'map(select(.amount >= 10)) | .[0]')

if [[ -z "$alice_utxo" || "$alice_utxo" == "null" ]]; then
  echo "Error: Alice no tiene UTXOs validos"
  exit 1
fi

if [[ -z "$bob_utxo" || "$bob_utxo" == "null" ]]; then
  echo "Error: Bob no tiene UTXOs validos"
  exit 1
fi

alice_txid=$(echo "$alice_utxo" | jq -r '.txid')
alice_vout=$(echo "$alice_utxo" | jq -r '.vout')
alice_amount=$(echo "$alice_utxo" | jq -r '.amount')

bob_txid=$(echo "$bob_utxo" | jq -r '.txid')
bob_vout=$(echo "$bob_utxo" | jq -r '.vout')
bob_amount=$(echo "$bob_utxo" | jq -r '.amount')

alice_change=$(echo "$alice_amount - $amount_required - $fee" | bc -l)
bob_change=$(echo "$bob_amount - $amount_required - $fee" | bc -l)

echo "Alice cambio: $alice_change BTC"
echo "Bob cambio: $bob_change BTC"

inputs=$(jq -n --arg atxid "$alice_txid" --argjson avout "$alice_vout" \
               --arg btxid "$bob_txid" --argjson bvout "$bob_vout" \
  '[{"txid": $atxid, "vout": $avout}, {"txid": $btxid, "vout": $bvout}]')

outputs=$(jq -n --arg multisig "$multisig_addr" \
               --arg alice_change "$alice_change_addr" \
               --arg bob_change "$bob_change_addr" \
               --argjson alice_amt "$alice_change" \
               --argjson bob_amt "$bob_change" \
               --argjson fund_amt 20 \
  '{
    ($multisig): $fund_amt,
    ($alice_change): $alice_amt,
    ($bob_change): $bob_amt
  }')

psbt=$(bitcoin-cli -regtest -rpcwallet=Alice createpsbt "$inputs" "$outputs" 0 true)
echo "PSBT creada"

psbt_signed_alice=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt "$psbt" | jq -r '.psbt')
echo "Alice firmo la PSBT :$(bitcoin-cli -regtest analyzepsbt "$psbt_signed_alice")"
psbt_signed_bob=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt "$psbt_signed_alice" | jq -r '.psbt')
echo "Bob firmo la PSBT :$(bitcoin-cli -regtest analyzepsbt "$psbt_signed_bob")"

finalized=$(bitcoin-cli -regtest finalizepsbt "$psbt_signed_bob")
final_tx_hex=$(echo "$finalized" | jq -r '.hex')
complete=$(echo "$finalized" | jq -r '.complete')

if [[ "$complete" != "true" ]]; then
  echo "Error: la transaccion no esta completamente firmada"
  exit 1
fi

txid=$(bitcoin-cli -regtest sendrawtransaction "$final_tx_hex")
echo "Transaccion enviada. TXID: $txid"

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null

echo "Saldos despues de enviar a multisig:"
echo "Saldo Alice: $(bitcoin-cli -rpcwallet=Alice getbalance) BTC"
echo "Saldo Bob: $(bitcoin-cli -rpcwallet=Bob getbalance) BTC"
echo "Saldo Multisig: $(bitcoin-cli -rpcwallet=Multisig getbalance) BTC"

echo
echo "Enviando desde multisig a Alice..."

alice_receive_addr=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "Alice Receive")
# Derivando direccion de cambio multisig
multisig_change_addr=$(bitcoin-cli -regtest deriveaddresses "$multisig_descriptor_checksum" "[1,1]" | jq -r '.[0]')

send_amount=3.0
fee=0.0005

multisig_utxos=$(bitcoin-cli -regtest -rpcwallet=Multisig listunspent)
selected_utxo=$(echo "$multisig_utxos" | jq -c --argjson min_amount "$(echo "$send_amount + $fee" | bc)" '
  map(select(.amount >= $min_amount)) | .[0]')

if [[ -z "$selected_utxo" || "$selected_utxo" == "null" ]]; then
  echo "Error: No se encontro UTXO suficiente en Multisig"
  exit 1
fi

multisig_txid=$(echo "$selected_utxo" | jq -r '.txid')
multisig_vout=$(echo "$selected_utxo" | jq -r '.vout')
selected_sum=$(echo "$selected_utxo" | jq -r '.amount')

change_amount=$(echo "$selected_sum - $send_amount - $fee" | bc)

echo "UTXO seleccionado: $selected_sum BTC"
echo "Cantidad de cambio: $change_amount BTC"

inputs=$(jq -n --arg txid "$multisig_txid" --argjson vout "$multisig_vout" '[{"txid": $txid, "vout": $vout}]')

outputs=$(jq -n --arg alice_addr "$alice_receive_addr" --argjson send_amt "$send_amount" \
                --arg multisig_change "$multisig_change_addr" --argjson change_amt "$change_amount" \
  '{
    ($alice_addr): $send_amt,
    ($multisig_change): $change_amt
  }')

psbt=$(bitcoin-cli -regtest -rpcwallet=Multisig createpsbt "$inputs" "$outputs" 0 true)
echo "PSBT creada"

psbt_signed_multisig=$(bitcoin-cli -regtest -rpcwallet=Multisig walletprocesspsbt "$psbt" | jq -r '.psbt')
echo "Multisig firmo la PSBT :$(bitcoin-cli -regtest analyzepsbt "$psbt_signed_multisig")"
psbt_signed_alice=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt "$psbt_signed_multisig" | jq -r '.psbt')
echo "Alice firmo la PSBT :$(bitcoin-cli -regtest analyzepsbt "$psbt_signed_alice")"
psbt_signed_bob=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt "$psbt_signed_alice" | jq -r '.psbt')
echo "Bob firmo la PSBT :$(bitcoin-cli -regtest analyzepsbt "$psbt_signed_bob")"

finalized=$(bitcoin-cli -regtest finalizepsbt "$psbt_signed_bob")
final_tx_hex=$(echo "$finalized" | jq -r '.hex')
complete=$(echo "$finalized" | jq -r '.complete')

if [[ "$complete" != "true" ]]; then
  echo "Error: la transaccion no esta completamente firmada"
  exit 1
fi

txid=$(bitcoin-cli -regtest sendrawtransaction "$final_tx_hex")
echo "Transaccion enviada. TXID: $txid"

miner_addr=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Miner Fondeo")
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null

echo
echo "Saldos finales:"
echo "Saldo Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"
echo "Saldo Bob: $(bitcoin-cli -regtest -rpcwallet=Bob getbalance) BTC"
echo "Saldo Multisig: $(bitcoin-cli -regtest -rpcwallet=Multisig getbalance) BTC"