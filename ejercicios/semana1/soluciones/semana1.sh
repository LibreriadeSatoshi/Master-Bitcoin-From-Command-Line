#!/usr/bin/env bash
# -------------------------------------------------------------------
# Semana 1 – Script para ejecutarse DENTRO del contenedor regtest
# Suposiciones:
#   • bitcoind ya está corriendo con regtest=1
#   • bitcoin-cli está disponible en $PATH
# -------------------------------------------------------------------
set -euo pipefail

echo "🔎 Verificando que estamos en regtest..."
bitcoin-cli getblockchaininfo | grep '"chain": "regtest"' >/dev/null

echo "👜 Creando wallets Miner y Trader (ignorar error si existen)…"
bitcoin-cli -regtest createwallet Miner   >/dev/null 2>&1 || true
bitcoin-cli -regtest createwallet Trader  >/dev/null 2>&1 || true

echo "⛏️ Minando 101 bloques para madurar recompensa..."
MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress)
bitcoin-cli -regtest generatetoaddress 101 "$MINER_ADDR" >/dev/null
echo "Saldo Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"

echo "💸 Enviando 20 BTC de Miner a Trader..."
TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress)
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)
echo "TXID: $TXID"

echo "🕒 En mempool:"
bitcoin-cli -regtest getmempoolentry "$TXID"

echo "🔒 Confirmando con 1 bloque..."
bitcoin-cli -regtest generatetoaddress 1 "$MINER_ADDR" >/dev/null

echo "📜 Detalles finales (perspectiva de Miner):"
bitcoin-cli -regtest -rpcwallet=Miner gettransaction "$TXID"

echo "📜 Detalles finales (perspectiva de Trader):"
bitcoin-cli -regtest -rpcwallet=Trader gettransaction "$TXID"

echo "Saldo Miner:  $(bitcoin-cli -regtest -rpcwallet=Miner  getbalance) BTC"
echo "Saldo Trader: $(bitcoin-cli -regtest -rpcwallet=Trader getbalance) BTC"