#!/bin/bash

# Bitcoin RBF y CPFP Exercise Script
# Autor: wersatoshi.sh

echo "=== Bitcoin RBF vs CPFP ==="
echo ""

# Iniciar Bitcoin Core
echo "Iniciando Bitcoin."
bitcoind -regtest -daemon
sleep 5
bitcoin-cli -regtest getblockchaininfo > /dev/null
echo "Bitcoin listo"
echo ""

# Paso 1: Crear billeteras
echo "Paso 1: Creando billeteras Miner y Trader"
if bitcoin-cli -regtest createwallet "Miner" 2>/dev/null; then
    echo "Miner creada"
else
    bitcoin-cli -regtest loadwallet "Miner" 2>/dev/null
    echo "Miner cargada"
fi

if bitcoin-cli -regtest createwallet "Trader" 2>/dev/null; then
    echo "Trader creada"
else
    bitcoin-cli -regtest loadwallet "Trader" 2>/dev/null
    echo "Trader cargada"
fi
echo ""

# Paso 2: Fondear Miner
echo "Paso 2: Fondeando Miner con 150 BTC"
MINER_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="Miner" getnewaddress)
bitcoin-cli -regtest generatetoaddress 105 "$MINER_ADDRESS" > /dev/null
BALANCE=$(bitcoin-cli -regtest -rpcwallet="Miner" getbalance)
echo "Saldo: $BALANCE BTC"
echo ""

# Paso 3: Crear transacción parent
echo "Paso 3: Creando transacción parent"
TRADER_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="Trader" getnewaddress)
MINER_CHANGE_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="Miner" getnewaddress)

INPUT1_TXID=$(bitcoin-cli -regtest -rpcwallet="Miner" listunspent | jq -r '.[] | select(.amount == 50) | .txid' | head -1)
INPUT1_VOUT=$(bitcoin-cli -regtest -rpcwallet="Miner" listunspent | jq -r '.[] | select(.amount == 50) | .vout' | head -1)
INPUT2_TXID=$(bitcoin-cli -regtest -rpcwallet="Miner" listunspent | jq -r '.[] | select(.amount == 50) | .txid' | head -2 | tail -1)
INPUT2_VOUT=$(bitcoin-cli -regtest -rpcwallet="Miner" listunspent | jq -r '.[] | select(.amount == 50) | .vout' | head -2 | tail -1)

PARENT_TX_RAW=$(bitcoin-cli -regtest createrawtransaction \
    "[{\"txid\":\"$INPUT1_TXID\",\"vout\":$INPUT1_VOUT,\"sequence\":4294967293},{\"txid\":\"$INPUT2_TXID\",\"vout\":$INPUT2_VOUT,\"sequence\":4294967293}]" \
    "{\"$TRADER_ADDRESS\":70,\"$MINER_CHANGE_ADDRESS\":29.99999}")

# Paso 4: Firmar y transmitir parent
echo "Paso 4: Firmando y transmitiendo parent"
PARENT_TX_SIGNED=$(bitcoin-cli -regtest -rpcwallet="Miner" signrawtransactionwithwallet "$PARENT_TX_RAW")
PARENT_TX_HEX=$(echo "$PARENT_TX_SIGNED" | jq -r '.hex')
PARENT_TXID=$(bitcoin-cli -regtest sendrawtransaction "$PARENT_TX_HEX")
echo "Parent enviado: $PARENT_TXID"
echo ""

# Paso 5: Consultar mempool y crear JSON
echo "Paso 5: Consultando mempool para parent"
PARENT_MEMPOOL_ENTRY=$(bitcoin-cli -regtest getmempoolentry "$PARENT_TXID")
PARENT_RAW_TX=$(bitcoin-cli -regtest getrawtransaction "$PARENT_TXID" true)
echo "$PARENT_MEMPOOL_ENTRY" | jq '.'

PARENT_WEIGHT=$(echo "$PARENT_MEMPOOL_ENTRY" | jq -r '.weight')
PARENT_FEES=$(echo "$PARENT_MEMPOOL_ENTRY" | jq -r '.fees.base')
MINER_SCRIPT_PUBKEY=$(echo "$PARENT_RAW_TX" | jq -r '.vout[1].scriptPubKey.hex')
TRADER_SCRIPT_PUBKEY=$(echo "$PARENT_RAW_TX" | jq -r '.vout[0].scriptPubKey.hex')

PARENT_JSON=$(jq -n \
    --arg input1_txid "$INPUT1_TXID" \
    --arg input1_vout "$INPUT1_VOUT" \
    --arg input2_txid "$INPUT2_TXID" \
    --arg input2_vout "$INPUT2_VOUT" \
    --arg miner_script "$MINER_SCRIPT_PUBKEY" \
    --arg miner_amount "29.99999" \
    --arg trader_script "$TRADER_SCRIPT_PUBKEY" \
    --arg trader_amount "70" \
    --arg fees "$PARENT_FEES" \
    --arg weight "$PARENT_WEIGHT" \
    '{
        "input": [
            {
                "txid": $input1_txid,
                "vout": $input1_vout
            },
            {
                "txid": $input2_txid,
                "vout": $input2_vout
            }
        ],
        "output": [
            {
                "script_pubkey": $miner_script,
                "amount": $miner_amount
            },
            {
                "script_pubkey": $trader_script,
                "amount": $trader_amount
            }
        ],
        "Fees": $fees,
        "Weight": $weight
    }')

# Paso 6: Imprimir JSON
echo ""
echo "Paso 6: JSON de la transacción parent"
echo "$PARENT_JSON" | jq '.'
echo ""

# Paso 7: Crear child
echo "Paso 7: Creando transacción child"
MINER_NEW_ADDRESS=$(bitcoin-cli -regtest -rpcwallet="Miner" getnewaddress)

CHILD_TX_RAW=$(bitcoin-cli -regtest createrawtransaction \
    "[{\"txid\":\"$PARENT_TXID\",\"vout\":1}]" \
    "{\"$MINER_NEW_ADDRESS\":29.99998}")

CHILD_TX_SIGNED=$(bitcoin-cli -regtest -rpcwallet="Miner" signrawtransactionwithwallet "$CHILD_TX_RAW")
CHILD_TX_HEX=$(echo "$CHILD_TX_SIGNED" | jq -r '.hex')
CHILD_TXID=$(bitcoin-cli -regtest sendrawtransaction "$CHILD_TX_HEX")
echo "Child enviado: $CHILD_TXID"
echo ""

# Paso 8: Consultar mempool para child
echo "Paso 8: getmempoolentry para child"
bitcoin-cli -regtest getmempoolentry "$CHILD_TXID" | jq '.'
echo ""

# Paso 9: Crear RBF
echo "Paso 9: Creando RBF para incrementar fee en 10,000 satoshis"
PARENT_RBF_TX_RAW=$(bitcoin-cli -regtest createrawtransaction \
    "[{\"txid\":\"$INPUT1_TXID\",\"vout\":$INPUT1_VOUT,\"sequence\":4294967293},{\"txid\":\"$INPUT2_TXID\",\"vout\":$INPUT2_VOUT,\"sequence\":4294967293}]" \
    "{\"$TRADER_ADDRESS\":70,\"$MINER_CHANGE_ADDRESS\":29.99989}")

# Paso 10: Firmar y transmitir RBF
echo "Paso 10: Firmando y transmitiendo nueva transacción parent"
PARENT_RBF_TX_SIGNED=$(bitcoin-cli -regtest -rpcwallet="Miner" signrawtransactionwithwallet "$PARENT_RBF_TX_RAW")
PARENT_RBF_TX_HEX=$(echo "$PARENT_RBF_TX_SIGNED" | jq -r '.hex')
PARENT_RBF_TXID=$(bitcoin-cli -regtest sendrawtransaction "$PARENT_RBF_TX_HEX")
echo "RBF enviado: $PARENT_RBF_TXID"
echo ""

# Paso 11: Consultar mempool para child después de RBF
echo "Paso 11: getmempoolentry para child después de RBF"
bitcoin-cli -regtest getmempoolentry "$CHILD_TXID" 2>/dev/null || echo "Error: No such mempool entry"
echo ""

# Paso 12: Explicación
echo "Paso 12: Explicación de los cambios"
echo ""
echo "¿Qué pasó con la transacción child?"
echo ""
echo "ANTES del RBF:"
echo "- Child estaba en el mempool funcionando normalmente"
echo "- Dependía del parent para ser válida"
echo ""
echo "DESPUÉS del RBF:"
echo "- Child desapareció completamente del mempool"
echo "- Ya no existe, como si nunca hubiera existido"
echo ""
echo "¿Por qué pasó esto?"
echo ""
echo "Cuando se hace RBF se esta creando una nueva versión del parent."
echo "Bitcoin elimina el parent original y pone el nuevo en su lugar."
echo "Pero el child original estaba conectado al parent original."
echo "Al desaparecer el parent originalel child queda sin padre."
echo "Bitcoin automáticamente borra las transacciones huérfanas."
echo ""
echo "En resumen:"
echo "No puedes usar RBF y CPFP al mismo tiempo en la misma cadena."
echo "Si haces RBF en una transacción que tiene hijos, los hijos desaparecen."
echo "Es como cortar la rama de un árbol - todo lo que colgaba de ella se cae."
echo ""

# Cerrar
echo "Cerrando Bitcoin"
bitcoin-cli -regtest stop
echo "Completado"
