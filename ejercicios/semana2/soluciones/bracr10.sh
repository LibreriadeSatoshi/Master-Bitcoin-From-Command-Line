#!/bin/bash

echo "Verificando dependencias necesarias..."

install_if_missing() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 no está instalado. Instalando..."
    sudo apt update
    sudo apt install -y "$2"
  else
    echo "$1 ya está instalado."
  fi
}

install_if_missing jq jq
install_if_missing bc bc

if pgrep -f "bitcoind.*-regtest" >/dev/null 2>&1; then
  echo "bitcoind ya está ejecutándose."
else
  echo "Iniciando bitcoind en regtest..."
  rm -rf "$BITCOIN_DIR/regtest"
  bitcoind -regtest -daemon
  sleep 5
fi

echo "Verificando y creando wallets si no existen..."

wallets=$(bitcoin-cli listwallets | jq -r '.[]')

if ! echo "$wallets" | grep -q "^Miner$"; then
  echo "Creando wallet 'Miner'..."
  bitcoin-cli createwallet "Miner" >/dev/null 2>&1
  echo "Wallet 'Miner' creada."
else
  echo "Wallet 'Miner' ya existe."
fi

if ! echo "$wallets" | grep -q "^Trader$"; then
  echo "Creando wallet 'Trader'..."
  bitcoin-cli createwallet "Trader" >/dev/null 2>&1
  echo "Wallet 'Trader' creada."
else
  echo "Wallet 'Trader' ya existe."
fi

sleep 2

echo "Generando dirección de Miner y minando bloques para recibir fondos..."

miner_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner Fondeo")

block_count=0
while [[ $block_count -lt 3 ]]; do
  bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1
  block_count=$((block_count + 1))
done

balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Saldo Miner: ${balance} BTC"

utxos=$(bitcoin-cli -rpcwallet=Miner listunspent)
inputs_json=$(jq -n '[]')

echo "Buscando UTXOs coinbase de 50 BTC..."

total_utxos=$(echo "$utxos" | jq 'length')

for ((i = 0; i < total_utxos; i++)); do
  if [[ $(echo "$inputs_json" | jq 'length') -eq 2 ]]; then
    break
  fi

  amount=$(echo "$utxos" | jq ".[$i].amount")
  is_fifty=$(echo "$amount == 50" | bc -l)

  if [[ "$is_fifty" -eq 1 ]]; then
    txid=$(echo "$utxos" | jq -r ".[$i].txid")
    vout=$(echo "$utxos" | jq ".[$i].vout")

    is_coinbase=$(bitcoin-cli getrawtransaction "$txid" true | jq '.vin[0] | has("coinbase")')

    if [[ "$is_coinbase" == "true" ]]; then
      new_input=$(jq -n --arg txid "$txid" --argjson vout "$vout" '[{txid: $txid, vout: $vout}]')
      inputs_json=$(echo "$inputs_json" | jq ". + $new_input")
    fi
  fi
done

utxos_count=$(echo "$inputs_json" | jq 'length')

if [[ "$utxos_count" -lt 2 ]]; then
  echo "No se encontraron 2 UTXOs coinbase de 50 BTC disponibles"
  echo "UTXOs encontrados: $utxos_count"
  echo "Se necesitan exactamente 2 UTXOs de 50 BTC cada uno"
  echo "El script se detiene...."
  exit 1
fi

echo "Se encontraron 2 UTXOs coinbase de 50 BTC"

trader_addr=$(bitcoin-cli -rpcwallet=Trader getnewaddress)
change_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress)

outputs_json=$(jq -n \
  --arg trader "$trader_addr" \
  --arg change "$change_addr" \
  '{($trader): 70, ($change): 29.99999}')

echo "Creando transacción parent..."

raw_parent=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "$inputs_json" "$outputs_json" 0 true)
signed_parent=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$raw_parent")

if [[ $(echo "$signed_parent" | jq -r '.complete') != "true" ]]; then
  echo "Error al firmar transacción parent"
  echo "$signed_parent" | jq -r '.errors[]'
  exit 1
fi

hex_parent=$(echo "$signed_parent" | jq -r '.hex')
parent_txid=$(bitcoin-cli sendrawtransaction "$hex_parent")

if [[ -z "$parent_txid" ]]; then
  echo "Error al transmitir transacción parent"
  exit 1
fi

echo "TX parent transmitida: $parent_txid"

decoded_parent=$(bitcoin-cli getrawtransaction "$parent_txid" true)
mempool_parent=$(bitcoin-cli getmempoolentry "$parent_txid")

inputs_arr=$(echo "$decoded_parent" | jq '[.vin[] | {txid: .txid, vout: .vout}]')
outputs_arr=$(echo "$decoded_parent" | jq '[.vout[] | {script_pubkey: .scriptPubKey.hex, amount: .value}]')

fee=$(echo "$mempool_parent" | jq -r '.fees.base')
weight=$(echo "$mempool_parent" | jq -r '.weight')
vbytes=$(echo "($weight + 3)/4" | bc)

summary=$(jq -n \
  --argjson inputs "$inputs_arr" \
  --argjson outputs "$outputs_arr" \
  --argjson fee "$fee" \
  --argjson weight "$vbytes" \
  '{input: $inputs, output: $outputs, fee: $fee, weight: $weight}')

echo "Resumen transacción parent:"
echo "$summary" | jq .

vout_data=$(echo "$decoded_parent" | jq '.vout')
vout_total=$(echo "$vout_data" | jq 'length')

out_index=""
out_amount=""

for ((i = 0; i < vout_total; i++)); do
  addr=$(echo "$vout_data" | jq -r ".[$i].scriptPubKey.address // empty")
  if [[ -z "$addr" ]]; then
    continue
  fi

  ismine=$(bitcoin-cli -rpcwallet=Miner getaddressinfo "$addr" | jq -r '.ismine // false')

  if [[ "$ismine" == "true" && "$addr" == "$change_addr" ]]; then
    out_index=$i
    out_amount=$(echo "$vout_data" | jq -r ".[$i].value")
    break
  fi
done

if [[ -z "$out_index" ]]; then
  echo "No se encontró salida del Miner"
  exit 1
fi

echo "Creando transacción child para CPFP..."

child_input=$(jq -n --arg txid "$parent_txid" --argjson vout "$out_index" '[{txid: $txid, vout: $vout}]')

new_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress)
amount_child=$(echo "$out_amount - 0.00001" | bc -l)

child_output=$(jq -n --arg addr "$new_addr" --arg amt "$amount_child" '{($addr): ($amt | tonumber)}')

raw_child=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "$child_input" "$child_output" 0 true)
signed_child=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$raw_child")

if [[ $(echo "$signed_child" | jq -r '.complete') != "true" ]]; then
  echo "Error al firmar transacción child"
  echo "$signed_child" | jq -r '.errors[]'
  exit 1
fi

hex_child=$(echo "$signed_child" | jq -r '.hex')
child_txid=$(bitcoin-cli sendrawtransaction "$hex_child")

if [[ -z "$child_txid" ]]; then
  echo "Error al transmitir transacción child"
  exit 1
fi

echo "TX child transmitida: $child_txid"

if ! bitcoin-cli getmempoolentry "$parent_txid" >/dev/null 2>&1; then
  echo "La transacción parent ya no está en mempool"
  exit 1
fi

new_fee=$(echo "$fee + 0.0001" | bc -l)
new_amount=$(echo "29.99999 - 0.0001" | bc -l)

echo "Recreando transacción parent con mayor fee (RBF)..."

rbf_outputs=$(jq -n \
  --arg trader "$trader_addr" \
  --arg change "$change_addr" \
  --arg amt "$new_amount" \
  '{($trader): 70, ($change): ($amt | tonumber)}')

rbf_raw=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "$inputs_json" "$rbf_outputs" 0 true)
rbf_signed=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$rbf_raw")

if [[ $(echo "$rbf_signed" | jq -r '.complete') != "true" ]]; then
  echo "Error al firmar transacción RBF"
  echo "$rbf_signed" | jq -r '.errors[]'
  exit 1
fi

hex_rbf=$(echo "$rbf_signed" | jq -r '.hex')
rbf_txid=$(bitcoin-cli sendrawtransaction "$hex_rbf")

if [[ -z "$rbf_txid" ]]; then
  echo "Error al transmitir transacción RBF"
  exit 1
fi

echo "TX RBF transmitida: $rbf_txid"

if bitcoin-cli getmempoolentry "$child_txid" >/dev/null 2>&1; then
  echo "La transacción child todavía está en mempool:"
else
  echo "La transacción child fue eliminada del mempool porque su parent fue reemplazada:"
fi

bitcoin-cli getmempoolentry "$child_txid" || true

echo "Estado final del mempool:"
bitcoin-cli getrawmempool

echo "Resumen del proceso:"
echo "1. Se creó una transacción parent con RBF habilitado y se envió."
echo "2. Se creó una transacción child (CPFP) que dependía de la parent para aumentar la fee."
echo "3. Luego, se reemplazó la parent con una versión de mayor fee usando RBF."
echo "4. Esto invalidó la transacción child, ya que su parent ya no existe en el mempool."
echo "5. Se demuestra que RBF y CPFP no pueden usarse simultáneamente."
echo "Proceso completado con éxito."
