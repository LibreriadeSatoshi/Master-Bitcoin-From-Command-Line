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
echo "Generando 101 bloques iniciales..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 101 "$miner_addr" >/dev/null 2>&1

employer_addr=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Empleador Fondeo")

echo
echo "Enviando 50 BTC al empleador..."
employer_txid=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$employer_addr" 50.0)
echo "Generando 10 bloques más para confirmar la transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 10 "$miner_addr" >/dev/null 2>&1

echo "Verificando balances:"
echo "Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"

echo
echo "Obteniendo detalles de la transacción del empleador..."
employer_tx_details=$(bitcoin-cli -regtest -rpcwallet=Empleador gettransaction "$employer_txid")
employer_vout=$(echo "$employer_tx_details" | jq -r '.details[] | select(.address == "'$employer_addr'") | .vout')

inputs_json=$(jq -n --arg txid "$employer_txid" --argjson vout "$employer_vout" '[{txid: $txid, vout: $vout}]')

employee_addr=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress "Salario")
change_addr=$(bitcoin-cli -regtest -rpcwallet=Empleador getnewaddress "Cambio")

echo "Dirección del empleado: $employee_addr"
echo "Dirección de cambio del empleador: $change_addr"

outputs_json=$(jq -n \
  --arg employee "$employee_addr" \
  --arg change "$change_addr" \
  '{($employee): 40, ($change): 9.9999}')

echo "Creando transacción de salario con timelock absoluto..."
echo "Configurando timelock absoluto para el bloque 500"
raw_parent=$(bitcoin-cli -regtest -rpcwallet=Empleador createrawtransaction "$inputs_json" "$outputs_json" 500 true)

echo
echo "Firmando transacción..."
signed_parent=$(bitcoin-cli -regtest -rpcwallet=Empleador signrawtransactionwithwallet "$raw_parent")

is_complete=$(echo "$signed_parent" | jq -r '.complete')
if [[ "$is_complete" != "true" ]]; then
  echo "Error: La transacción no pudo ser firmada completamente"
  echo "$signed_parent" | jq '.'
  exit 1
fi

signed_hex=$(echo "$signed_parent" | jq -r '.hex')
echo "Transacción firmada exitosamente"

current_height=$(bitcoin-cli -regtest getblockcount)
echo "Altura actual de la blockchain: $current_height"

echo "Esperando a que se alcance el bloque 500..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 500 "$miner_addr" >/dev/null 2>&1
sleep 2

salary_txid=$(bitcoin-cli -regtest sendrawtransaction "$signed_hex")
echo "Resultado de la transmisión: $salary_txid"

echo "Confirmando transacción..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1

echo
echo "Transacción de salario transmitida exitosamente con timelock absoluto!"
echo "Saldos después de la transmisión:"
echo "Empleador: $(bitcoin-cli -regtest -rpcwallet=Empleador getbalance) BTC"
echo "Empleado: $(bitcoin-cli -regtest -rpcwallet=Empleado getbalance) BTC"
echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"

echo "Obteniendo detalles de la transacción de salario..."
salary_tx_details=$(bitcoin-cli -regtest -rpcwallet=Empleado gettransaction "$salary_txid")
employee_vout=$(echo "$salary_tx_details" | jq -r '.details[] | select(.address == "'$employee_addr'") | .vout')

employee_inputs_json=$(jq -n --arg txid "$salary_txid" --argjson vout "$employee_vout" '[{txid: $txid, vout: $vout}]')

employee_spending_addr=$(bitcoin-cli -regtest -rpcwallet=Empleado getnewaddress "Gasto Empleado")

echo
echo "Procesando mensaje OP_RETURN..."
message="He recibido mi salario, ahora soy rico"
echo "Mensaje original: '$message'"

hex_data=$(echo -n "$message" | xxd -p | tr -d '\n')
echo "Datos hexadecimales: $hex_data"

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

echo "OP_RETURN en la transacción de gasto:"
decoded_tx=$(bitcoin-cli -regtest decoderawtransaction "$signed_spending_hex")
mensaje=$(echo "$decoded_tx" | jq -r '.vout[] | select(.scriptPubKey.type == "nulldata") | .scriptPubKey.hex')
echo "Mensaje decodificado: $(echo "${mensaje:4}" | xxd -r -p)"