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
install_if_missing xxd vim-common

BITCOIN_DIR=${BITCOIN_DIR:-~/.bitcoin}

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

wallets=$(bitcoin-cli -regtest listwallets | jq -r '.[]')

for w in Miner Empleado Empleador; do
  if ! echo "$wallets" | grep -q "^$w$"; then
    echo "Creando wallet '$w'..."
    bitcoin-cli -regtest createwallet "$w" >/dev/null 2>&1
  else
    echo "Wallet '$w' ya existe"
  fi
done

sleep 2

echo
echo "Generando fondos iniciales..."

miner_addr=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Miner Fondeo")
echo "Generando 101 bloques iniciales ..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 101 "$miner_addr" >/dev/null 2>&1

employer_addr=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Empleador Fondeo")

echo "Enviando 50 BTC al empleador..."
bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$employer_addr" 50.0 >/dev/null 2>&1
echo "Generando 10 bloques más para confirmar la transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 10 "$miner_addr" >/dev/null 2>&1

echo
echo "Verificando balances:"
echo "Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"

echo
echo "Buscando UTXO de 50 BTC del empleador..."

utxos=$(bitcoin-cli -regtest -rpcwallet=Empleador listunspent)
total_utxos=$(echo "$utxos" | jq 'length')
inputs_json=$(jq -n '[]')

for ((i = 0; i < total_utxos; i++)); do
  if [[ $(echo "$inputs_json" | jq 'length') -eq 1 ]]; then
    break
  fi

  amount=$(echo "$utxos" | jq ".[$i].amount")
  is_fifty=$(echo "$amount == 50" | bc -l)

  if [[ "$is_fifty" -eq 1 ]]; then
    txid=$(echo "$utxos" | jq -r ".[$i].txid")
    vout=$(echo "$utxos" | jq ".[$i].vout")
    new_input=$(jq -n --arg txid "$txid" --argjson vout "$vout" '[{txid: $txid, vout: $vout}]')
    inputs_json=$(echo "$inputs_json" | jq ". + $new_input")
    echo "Encontrado UTXO de 50 BTC"
  fi
done

utxos_count=$(echo "$inputs_json" | jq 'length')

if [[ "$utxos_count" -lt 1 ]]; then
  echo "No se encontraron UTXOs de 50 BTC disponibles"
  echo "UTXOs encontrados: $utxos_count"
  echo "El script se detiene...."
  exit 1
fi

echo 

employee_addr=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress "Salario")
change_addr=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Cambio")

echo "Dirección del empleado: $employee_addr"
echo "Dirección de cambio del empleador: $change_addr"

# Crear outputs: 40 BTC para empleado, 9.9999 BTC de cambio y 0.0001 BTC de fee
outputs_json=$(jq -n \
  --arg employee "$employee_addr" \
  --arg change "$change_addr" \
  '{($employee): 40, ($change): 9.9999}')

echo
echo "Creando transacción de salario con timelock absoluto..."

echo "Configurando timelock absoluto para el bloque 500"
raw_parent=$(bitcoin-cli -regtest -rpcwallet=Empleador createrawtransaction "$inputs_json" "$outputs_json" 500 true)

echo "Firmando transacción..."
signed_parent=$(bitcoin-cli -regtest -rpcwallet=Empleador signrawtransactionwithwallet "$raw_parent")

is_complete=$(echo "$signed_parent" | jq -r '.complete')
if [[ "$is_complete" != "true" ]]; then
  echo "Error: La transacción no pudo ser firmada completamente"
  echo "$signed_parent" | jq '.'
  exit 1
fi

signed_hex=$(echo "$signed_parent" | jq -r '.hex')
echo "Transacción firmada exitosamente $signed_hex"

current_height=$(bitcoin-cli -regtest getblockcount)
echo
echo "Altura actual de la blockchain: $current_height"
if [[ $current_height -ge 500 ]]; then
  echo "La altura actual es mayor o igual a 500, la transacción se puede transmitir inmediatamente."
else
  echo "La altura actual es menor a 500, la transacción no se puede transmitir hasta alcanzar el bloque 500."
fi
echo
echo "Intentando transmitir la transacción con timelock..."

if transmission_result=$(bitcoin-cli -regtest sendrawtransaction "$signed_hex" 2>&1); then
  echo "Transacción transmitida exitosamente!"
  echo "TXID: $transmission_result"
else
  echo "Error al transmitir la transacción:"
  echo
  echo "$transmission_result"
  echo
  echo "La transacción tiene un timelock absoluto y no se puede transmitir hasta que se alcance el bloque 500."
fi

echo "Esperando a que se alcance el bloque 500 o mas para transmitir la transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 500 "$miner_addr" >/dev/null 2>&1
sleep 2

transmission_result=$(bitcoin-cli -regtest sendrawtransaction "$signed_hex" 2>&1)
echo "Resultado de la transmisión: $transmission_result"
echo "Esperando a que se confirme la transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1

echo
echo "Transacción transmitida exitosamente con timelock absoluto!"
echo "Saldos después de la transmisión:"
echo "Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"
echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
echo

echo "Buscando UTXOs del empleado para gastar..."
employee_utxos=$(bitcoin-cli -regtest -rpcwallet=Empleado listunspent)
total_employee_utxos=$(echo "$employee_utxos" | jq 'length')

if [[ "$total_employee_utxos" -eq 0 ]]; then
  echo "Error: El empleado no tiene UTXOs disponibles para gastar"
  exit 1
fi

employee_inputs_json=$(jq -n '[]')
selected_amount=0

for ((i = 0; i < total_employee_utxos; i++)); do
  amount=$(echo "$employee_utxos" | jq ".[$i].amount")
  is_forty=$(echo "$amount == 40" | bc -l)
  
  if [[ "$is_forty" -eq 1 ]]; then
    txid=$(echo "$employee_utxos" | jq -r ".[$i].txid")
    vout=$(echo "$employee_utxos" | jq ".[$i].vout")
    new_input=$(jq -n --arg txid "$txid" --argjson vout "$vout" '[{txid: $txid, vout: $vout}]')
    employee_inputs_json=$(echo "$employee_inputs_json" | jq ". + $new_input")
    selected_amount=$(echo "$selected_amount + $amount" | bc -l)
    echo "Seleccionado UTXO de $amount BTC"
    break
  fi
done

if [[ $(echo "$selected_amount == 0" | bc -l) -eq 1 ]]; then
  echo "Error: No se encontró UTXO de 40 BTC del empleado"
  exit 1
fi

echo "Total seleccionado para gastar: $selected_amount BTC"

employee_spending_addr=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress "Gasto Empleado")

echo "Procesando mensaje OP_RETURN ..."
message="He recibido mi salario, ahora soy rico"
echo "Mensaje original: '$message'"

echo "Convirtiendo texto a hexadecimal..."
hex_data=$(echo -n "$message" | xxd -p | tr -d '\n')
echo "Datos hexadecimales: $hex_data"
echo "Longitud del mensaje: ${#message} caracteres"
echo "Longitud hexadecimal: ${#hex_data} caracteres"

spending_outputs_json=$(jq -n \
  --arg employee_spend "$employee_spending_addr" \
  --arg hex_data "$hex_data" \
  '{($employee_spend): 39.9999, "data": $hex_data}')

echo "Creando transacción de gasto del empleado con OP_RETURN..."

raw_spending_tx=$(bitcoin-cli -regtest -rpcwallet=Empleado createrawtransaction "$employee_inputs_json" "$spending_outputs_json" 0 true)

echo "Firmando transacción de gasto..."
signed_spending_tx=$(bitcoin-cli -regtest -rpcwallet=Empleado signrawtransactionwithwallet "$raw_spending_tx")

is_spending_complete=$(echo "$signed_spending_tx" | jq -r '.complete')
if [[ "$is_spending_complete" != "true" ]]; then
  echo "Error: La transacción de gasto no pudo ser firmada completamente"
  echo "$signed_spending_tx" | jq '.'
  exit 1
fi

signed_spending_hex=$(echo "$signed_spending_tx" | jq -r '.hex')
echo "Transacción de gasto firmada exitosamente"

spending_txid=$(bitcoin-cli -regtest sendrawtransaction "$signed_spending_hex")
echo "TXID de gasto: $spending_txid"

echo "Confirmando transacción de gasto..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1

echo
echo "Saldo final después de la transacción de gasto:"
echo "Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"
echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"

echo
echo "OP_RETURN en la transacción de gasto:"
decoded_tx=$(bitcoin-cli -regtest decoderawtransaction "$signed_spending_hex")
echo "$decoded_tx" | jq .
mensaje=$(echo "$decoded_tx" | jq -r '.vout[] | select(.scriptPubKey.type == "nulldata") | .scriptPubKey.hex')
echo "Mensaje decodificado: $(echo "${mensaje:4}" | xxd -r -p)"