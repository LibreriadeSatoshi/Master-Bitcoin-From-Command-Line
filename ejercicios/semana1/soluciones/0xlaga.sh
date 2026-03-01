#!/bin/bash
# Autor: 0xlaga
# Script para automatizar el reto de nodo Bitcoin en regtest

set -e

# Variables
BITCOIN_DIR="$HOME/.bitcoin"
CONF_FILE="$BITCOIN_DIR/bitcoin.conf"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"
MINER_LABEL="Recompensa de Mineria"
TRADER_LABEL="Recibido"
AMOUNT=20
FEE=0.0001

# 1. Configuración de bitcoin.conf
mkdir -p "$BITCOIN_DIR"
echo -e "regtest=1\nfallbackfee=$FEE\nserver=1\ntxindex=1" > "$CONF_FILE"
echo "Archivo bitcoin.conf configurado."

# 2. Iniciar bitcoind en regtest
bitcoind -regtest -daemon -deprecatedrpc=settxfee
sleep 3

echo "Esperando a que el nodo esté listo..."
while ! bitcoin-cli -regtest getblockchaininfo &>/dev/null; do sleep 1; done

echo "Nodo iniciado en regtest."

# 3. Crear o cargar billeteras
for WALLET in "$MINER_WALLET" "$TRADER_WALLET"; do
  if bitcoin-cli -regtest -rpcwallet="$WALLET" getwalletinfo &>/dev/null; then
    echo "Billetera $WALLET ya existe, cargando..."
    bitcoin-cli -regtest loadwallet "$WALLET" 2>/dev/null || true
  else
    bitcoin-cli -regtest createwallet "$WALLET" || true
  fi
done
    # Cargar billeteras si no están cargadas
for WALLET in "$MINER_WALLET" "$TRADER_WALLET"; do
  bitcoin-cli -regtest loadwallet "$WALLET" 2>/dev/null || true
done

echo "Billeteras listas."

# 4. Generar dirección para minar
MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET getnewaddress "$MINER_LABEL")
echo "Dirección de minado: $MINER_ADDR"

# 5. Minar bloques hasta saldo positivo
bitcoin-cli -regtest -rpcwallet=$MINER_WALLET generatetoaddress 101 "$MINER_ADDR"
SALDO=$(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET getbalance)
echo "Saldo de Miner tras minar 101 bloques: $SALDO BTC"

# 6. Crear dirección de Trader
TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=$TRADER_WALLET getnewaddress "$TRADER_LABEL")
echo "Dirección de Trader: $TRADER_ADDR"

# 7. Configurar fee y enviar 20 BTC
bitcoin-cli -regtest -rpcwallet=$MINER_WALLET settxfee $FEE
TXID=$(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET sendtoaddress "$TRADER_ADDR" $AMOUNT "Pago a Trader")
echo "TXID de envío: $TXID"

# 8. Mostrar transacción en mempool
bitcoin-cli -regtest getmempoolentry "$TXID"

# 9. Confirmar transacción minando un bloque
MINER_ADDR2=$(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET getnewaddress "Miner")
bitcoin-cli -regtest -rpcwallet=$MINER_WALLET generatetoaddress 1 "$MINER_ADDR2"

echo "Transacción confirmada. Detalles:"
bitcoin-cli -regtest getrawtransaction "$TXID" true $(bitcoin-cli -regtest getblockhash $(bitcoin-cli -regtest getblockcount))

echo "Saldo final de Miner: $(bitcoin-cli -regtest -rpcwallet=$MINER_WALLET getbalance) BTC"
echo "Saldo final de Trader: $(bitcoin-cli -regtest -rpcwallet=$TRADER_WALLET getbalance) BTC"
