#!/bin/bash
# Autor: 0xlaga
# Script para automatizar el reto de la semana 2: RBF y CPFP en regtest
set -e

BITCOIN_DIR="$HOME/.bitcoin"
CONF_FILE="$BITCOIN_DIR/bitcoin.conf"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"


# 1. Configuración de bitcoin.conf - 
mkdir -p ~/.bitcoin
echo -e "regtest=1\nfallbackfee=0.0001\nserver=1\ntxindex=1" > ~/.bitcoin/bitcoin.conf


# 2. Iniciar bitcoind en regtest
echo "Iniciando bitcoind..."
bitcoind -regtest -daemon -deprecatedrpc=settxfee
sleep 3
until bitcoin-cli -regtest getblockchaininfo &>/dev/null; do sleep 1; done
echo "Nodo listo."


# 3. Crear o cargar billeteras
for WALLET in Miner Trader; do
  bitcoin-cli -regtest loadwallet $WALLET 2>/dev/null || bitcoin-cli -regtest createwallet $WALLET
done
echo "Billeteras listas."



# 4. Minar fondos para Miner y asegurar 2 UTXOs de 50 BTC
MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress)
TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress)

while true; do
  bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 $MINER_ADDR > /dev/null
  UTXOS=$(bitcoin-cli -regtest -rpcwallet=Miner listunspent | jq '[.[] | select(.amount==50.00000000)]')
  [ $(echo "$UTXOS" | jq 'length') -ge 2 ] && break
done

IN0_TXID=$(echo $UTXOS | jq -r '.[0].txid')
IN0_VOUT=$(echo $UTXOS | jq -r '.[0].vout')
IN1_TXID=$(echo $UTXOS | jq -r '.[1].txid')
IN1_VOUT=$(echo $UTXOS | jq -r '.[1].vout')

if [ -z "$IN0_TXID" ] || [ -z "$IN1_TXID" ]; then
  echo "Error: No se encontraron dos UTXOs de 50 BTC disponibles para Miner."
  exit 1
fi


# 7. Construir transacción parent (RBF)
PARENT_RAW=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$IN0_TXID\",\"vout\":$IN0_VOUT,\"sequence\":4294967293},{\"txid\":\"$IN1_TXID\",\"vout\":$IN1_VOUT,\"sequence\":4294967293}]" "{\"$TRADER_ADDR\":70,\"$MINER_ADDR\":29.99999}")
PARENT_SIGNED=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet $PARENT_RAW | jq -r .hex)
PARENT_TXID=$(bitcoin-cli -regtest sendrawtransaction $PARENT_SIGNED)
echo "Parent TXID: $PARENT_TXID"

# 8. Consultar y mostrar JSON de la parent
echo "JSON parent (mempool):"
bitcoin-cli -regtest getmempoolentry $PARENT_TXID | jq
echo "JSON parent (decoded):"
bitcoin-cli -regtest getrawtransaction $PARENT_TXID true | jq


# 9. Crear y transmitir la child (CPFP)
CHILD_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress)
CHILD_RAW=$(bitcoin-cli -regtest createrawtransaction "[{\"txid\":\"$PARENT_TXID\",\"vout\":1}]" "{\"$CHILD_ADDR\":29.9998}")
CHILD_SIGNED=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet $CHILD_RAW | jq -r .hex)
CHILD_TXID=$(bitcoin-cli -regtest sendrawtransaction $CHILD_SIGNED)
echo "Child TXID: $CHILD_TXID"


# 10. Consultar mempool de la child
echo "Mempool child:"
bitcoin-cli -regtest getmempoolentry $CHILD_TXID | jq

# 11. Intentar bumpfee de la parent (debe fallar)
set +e
BUMP_RESULT=$(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET bumpfee $PARENT_TXID 2>&1)
set -e
echo "Intento de bumpfee sobre parent:"
echo "$BUMP_RESULT"

# 12. Explicación final
echo "\nExplicación:"
echo "No es posible hacer bumpfee (RBF) sobre la parent si tiene descendientes (child CPFP) en el mempool. El fee total para la confirmación de ambas dependerá del fee combinado. El CPFP permite que ambas sean confirmadas juntas si el fee es suficiente."
