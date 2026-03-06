#!/bin/bash

# Alias para facilitar los comandos
shopt -s expand_aliases
alias bcli="bitcoin-cli -regtest"

echo "--- 1. Creando billeteras Miner y Trader ---"
bcli -named createwallet wallet_name="Miner" >/dev/null 2>&1
bcli -named createwallet wallet_name="Trader" >/dev/null 2>&1

echo "--- 2. Fondeando la billetera Miner con 150 BTC ---"
MINER_ADDR=$(bcli -rpcwallet="Miner" getnewaddress)
bcli generatetoaddress 103 "$MINER_ADDR" >/dev/null

echo "--- 3. Creando transaccion Parent (con RBF) ---"
# Obtener dos UTXOs de 50 BTC
UTXO1_TXID=$(bcli -rpcwallet="Miner" listunspent | jq -r '.[0].txid')
UTXO1_VOUT=$(bcli -rpcwallet="Miner" listunspent | jq -r '.[0].vout')
UTXO2_TXID=$(bcli -rpcwallet="Miner" listunspent | jq -r '.[1].txid')
UTXO2_VOUT=$(bcli -rpcwallet="Miner" listunspent | jq -r '.[1].vout')

TRADER_ADDR=$(bcli -rpcwallet="Trader" getnewaddress)
MINER_CHANGE_ADDR=$(bcli -rpcwallet="Miner" getrawchangeaddress)

# Crear transaccion con sequence 1 para activar RBF
RAW_PARENT_TX=$(bcli -named createrawtransaction inputs='''[{"txid":"'''$UTXO1_TXID'''","vout":'''$UTXO1_VOUT''',"sequence":1},{"txid":"'''$UTXO2_TXID'''","vout":'''$UTXO2_VOUT''',"sequence":1}]''' outputs='''{"'''$TRADER_ADDR'''":70,"'''$MINER_CHANGE_ADDR'''":29.99999}''')

SIGNED_PARENT_TX=$(bcli -rpcwallet="Miner" signrawtransactionwithwallet "$RAW_PARENT_TX" | jq -r '.hex')
PARENT_TXID=$(bcli sendrawtransaction "$SIGNED_PARENT_TX")

echo "--- 4. Generando JSON de la transaccion Parent ---"
FEE=$(bcli getmempoolentry "$PARENT_TXID" | jq -r '.fees.base')
WEIGHT=$(bcli getmempoolentry "$PARENT_TXID" | jq -r '.weight')

jq -n \
  --arg txid1 "$UTXO1_TXID" --arg vout1 "$UTXO1_VOUT" \
  --arg txid2 "$UTXO2_TXID" --arg vout2 "$UTXO2_VOUT" \
  --arg spk1 "$MINER_CHANGE_ADDR" --arg amt1 "29.99999" \
  --arg spk2 "$TRADER_ADDR" --arg amt2 "70" \
  --arg fee "$FEE" --arg weight "$WEIGHT" \
  '{
    input: [
      {txid: $txid1, vout: $vout1},
      {txid: $txid2, vout: $vout2}
    ],
    output: [
      {script_pubkey: $spk1, amount: $amt1},
      {script_pubkey: $spk2, amount: $amt2}
    ],
    Fees: $fee,
    Weight: $weight
  }'

echo "--- 5. Creando transaccion Child ---"
# La entrada es el cambio del minero (vout 1 de la tx parent)
NEW_MINER_ADDR=$(bcli -rpcwallet="Miner" getnewaddress)
RAW_CHILD_TX=$(bcli -named createrawtransaction inputs='''[{"txid":"'''$PARENT_TXID'''","vout":1}]''' outputs='''{"'''$NEW_MINER_ADDR'''":29.99998}''')
SIGNED_CHILD_TX=$(bcli -rpcwallet="Miner" signrawtransactionwithwallet "$RAW_CHILD_TX" | jq -r '.hex')
CHILD_TXID=$(bcli sendrawtransaction "$SIGNED_CHILD_TX")

echo "Consulta Mempool Transaccion Child (Antes del RBF):"
bcli getmempoolentry "$CHILD_TXID"

echo "--- 6. Aumentando tarifa con RBF (Reemplazo Manual) ---"
# Misma entrada, diferente salida de cambio (restando 10,000 sats = 0.0001 BTC a la salida del minero)
# 29.99999 - 0.0001 = 29.99989
RBF_PARENT_TX=$(bcli -named createrawtransaction inputs='''[{"txid":"'''$UTXO1_TXID'''","vout":'''$UTXO1_VOUT''',"sequence":1},{"txid":"'''$UTXO2_TXID'''","vout":'''$UTXO2_VOUT''',"sequence":1}]''' outputs='''{"'''$TRADER_ADDR'''":70,"'''$MINER_CHANGE_ADDR'''":29.99989}''')

SIGNED_RBF_PARENT=$(bcli -rpcwallet="Miner" signrawtransactionwithwallet "$RBF_PARENT_TX" | jq -r '.hex')
NEW_PARENT_TXID=$(bcli sendrawtransaction "$SIGNED_RBF_PARENT")

echo "Consulta Mempool Transaccion Child (Despues del RBF):"
bcli getmempoolentry "$CHILD_TXID" || echo "Error esperado: La transacción Child no se encontró en la mempool."

echo "--- EXPLICACION ---"
echo "La primera consulta a la mempool mostró los detalles de la transacción Child porque su transacción Parent original era válida y existía en la mempool."
echo "Al aplicar RBF, creamos una nueva transacción Parent que gastaba las mismas entradas pero pagaba una mayor comisión, reemplazando a la original."
echo "Al desaparecer la Parent original, la transacción Child quedó intentando gastar una salida (UTXO) que ya no existe. Por lo tanto, el nodo la invalidó y la eliminó automáticamente de la mempool, resultando en el error -5."
