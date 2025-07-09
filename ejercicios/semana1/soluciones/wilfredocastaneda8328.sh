#!/bin/bash

# --- Configuración oficial según bitcoin.org ---
VERSION="29.0"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-$VERSION"
# Clave principal de Wladimir van der Laan
SIGNING_KEYS="01EA5486DE18A882D4C2684590C8019E36C2E964"

# --- 1. Descarga y verificación
echo "=== PASO 1: Descarga y verificación ==="

# Descargar archivos
echo "Descargando binarios v$VERSION..."
wget -q $BASE_URL/bitcoin-$VERSION-x86_64-linux-gnu.tar.gz || { echo "❌ Error: Fallo al descargar binarios"; exit 1; }
wget -q $BASE_URL/SHA256SUMS || { echo "❌ Error: Fallo al descargar hashes"; exit 1; }
wget -q $BASE_URL/SHA256SUMS.asc || { echo "❌ Error: Fallo al descargar firmas"; exit 1; }

# Verificación de hashes
echo "Verificando hashes..."
sha256sum --ignore-missing --check SHA256SUMS 2>/dev/null | grep "OK" && echo "✅ Hash verificado correctamente" || { echo "❌ Error: ¡Hash no coincide!"; exit 1; }

# Verificación GPG (proceso completo)
echo "Verificando firmas..."
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys $SIGNING_KEYS >/dev/null 2>&1
gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -q "Good signature" && echo "✅ Verificación exitosa de la firma binaria" || { echo "❌ Error: ¡Firma GPG inválida!"; exit 1; }

# Instalación
echo "Instalando binarios..."
tar -xzf bitcoin-$VERSION-x86_64-linux-gnu.tar.gz
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-$VERSION/bin/*

# --- 2. Configuración regtest ---
echo -e "\n=== PASO 2: Configuración regtest ==="
CONF_DIR="$HOME/.bitcoin"
CONF_FILE="$CONF_DIR/bitcoin.conf"

mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<EOF
# Configuración regtest (https://bitcoincore.org/en/doc/29.0/rpc/)
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

# Iniciar nodo
echo "Iniciando bitcoind en regtest..."
bitcoind -daemon
sleep 5 # Esperar inicialización

# --- 3. Configuración billeteras ---
echo -e "\n=== PASO 3: Configuración inicial ==="

# Crear billeteras
bitcoin-cli -regtest createwallet "Miner" >/dev/null
bitcoin-cli -regtest createwallet "Trader" >/dev/null

# Minar bloques iniciales (101 para recompensas maduras)
MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "Minando 101 bloques a $MINER_ADDR..."
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 101 "$MINER_ADDR" >/dev/null

# Verificar saldo
BLOCKS_NEEDED=101
MINER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
echo -e "\n💵 Saldo Miner: $MINER_BALANCE BTC (tras $BLOCKS_NEEDED bloques)"

# --- Explicación técnica ---
echo -e "\n📝 Explicación:"
echo "En Bitcoin, las recompensas de bloque necesitan 100 confirmaciones para madurar."
echo "Por eso minamos 101 bloques: 1 bloque genera la recompensa + 100 bloques de maduración."

# --- 4. Demostración transacción ---
echo -e "\n=== PASO 4: Transacción de prueba ==="
TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Recibido")
echo "Enviando 20 BTC a Trader..."
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)

# Confirmar transacción
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" >/dev/null

# Mostrar detalles
echo -e "\n🔍 Detalles de transacción:"
echo "TXID: $TXID"
echo "From Miner: 20 BTC"
echo "To Trader: $(bitcoin-cli -regtest -rpcwallet=Trader getreceivedbyaddress "$TRADER_ADDR") BTC"
echo -e "\n💰 Saldos finales:"
echo "Miner: $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
echo "Trader: $(bitcoin-cli -regtest -rpcwallet=Trader getbalance) BTC"

# --- Finalización ---
echo -e "\n🎉 ¡Configuración completada!"
echo "Para detener: bitcoin-cli -regtest stop"
