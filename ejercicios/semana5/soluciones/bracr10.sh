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

for w in Miner Alice; do
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

alice_addr=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "Alice Fondeo")

echo
echo "Enviando 20 BTC a Alice..."
alice_txid=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$alice_addr" 20.0)
echo "Generando 1 bloque para confirmar la transaccion..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1

echo "Verificando balances:"
echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
echo "Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"

echo
echo "Obteniendo detalles de la transaccion de Alice..."
alice_tx_details=$(bitcoin-cli -regtest -rpcwallet=Alice gettransaction "$alice_txid")
alice_vout=$(echo "$alice_tx_details" | jq -r '.details[] | select(.address == "'$alice_addr'") | .vout')

alice_block_height=$(echo "$alice_tx_details" | jq -r '.blockheight')
echo "Transaccion de Alice confirmada en bloque: $alice_block_height"

miner_payment_addr=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Pago")
alice_change_addr=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "Cambio")

outputs_json=$(jq -n \
  --arg miner "$miner_payment_addr" \
  --arg change "$alice_change_addr" \
  '{($miner): 10, ($change): 9.9999}')

echo
echo "Creando transaccion con timelock relativo de 10 bloques..."

# Para timelock relativo basado en bloques nSequence = número de bloques
# El valor debe tener el bit 31 desactivado  y bit 22 desactivado para bloques en formato hexadecimal little-endian 
BLOCKS_TO_WAIT=10
SEQUENCE_VALUE=$BLOCKS_TO_WAIT

echo "Usando nSequence = $SEQUENCE_VALUE para timelock relativo de $BLOCKS_TO_WAIT bloques"

inputs_json=$(jq -n \
  --arg txid "$alice_txid" \
  --argjson vout "$alice_vout" \
  --argjson seq "$SEQUENCE_VALUE" \
  '[{txid: $txid, vout: $vout, sequence: $seq}]')

raw_timelock=$(bitcoin-cli -regtest createrawtransaction "$inputs_json" "$outputs_json")

decoded_tx=$(bitcoin-cli -regtest decoderawtransaction "$raw_timelock")
actual_sequence=$(echo "$decoded_tx" | jq -r '.vin[0].sequence')

echo
echo "Firmando transaccion..."
signed_timelock=$(bitcoin-cli -regtest -rpcwallet=Alice signrawtransactionwithwallet "$raw_timelock")

is_complete=$(echo "$signed_timelock" | jq -r '.complete')
if [[ "$is_complete" != "true" ]]; then
  echo "Error: La transaccion no pudo ser firmada completamente"
  exit 1
fi

signed_hex=$(echo "$signed_timelock" | jq -r '.hex')
echo "Transaccion firmada exitosamente"

current_height=$(bitcoin-cli -regtest getblockcount)
echo "Altura actual de la blockchain: $current_height"
echo "Altura del bloque de confirmación: $alice_block_height"
echo "Bloques transcurridos desde confirmación del input de Alice: $((current_height - alice_block_height))"
echo "Bloques necesarios para el timelock: $BLOCKS_TO_WAIT"

echo
echo "Intentando hacer broadcoast de la transaccion con timelock relativo..."
if txid_result=$(bitcoin-cli -regtest sendrawtransaction "$signed_hex" 2>&1); then
    echo "La transaccion se envio inmediatamente. El timelock relativo no funciono correctamente."
    echo "Esto indica un problema en la configuracion del nSequence."
    echo "Respuesta de bitcoin-cli:"
    echo "$txid_result"
else
    echo
    echo "Transaccion rechazada por timelock relativo"
    echo "Respuesta de bitcoin-cli:"
    echo "$txid_result"

    echo
    blocks_needed=$((BLOCKS_TO_WAIT - (current_height - alice_block_height)))
    if [ $blocks_needed -gt 0 ]; then
        echo "Generando $blocks_needed bloques adicionales para satisfacer el timelock..."
        bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress $blocks_needed "$miner_addr" >/dev/null 2>&1
    fi
    
    echo "Reintentando envio despues del timelock..."
    txid_result=$(bitcoin-cli -regtest sendrawtransaction "$signed_hex")
    echo "Transaccion enviada exitosamente: $txid_result"
    
    bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$miner_addr" >/dev/null 2>&1
    
    echo
    echo "Balances finales:"
    echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
    echo "Alice: $(bitcoin-cli -regtest -rpcwallet=Alice getbalance) BTC"
    echo
fi