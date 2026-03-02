#!/usr/bin/env bash
# Ejercicio Semana 1 — Maestros de Bitcoin desde la línea de comandos
# Librería de Satoshi — MBFCL
#
# Este script realiza todos los pasos del ejercicio de la semana 1:
#   - Setup: descarga, verifica e instala Bitcoin Core 29.0
#   - Init:  configura regtest, crea wallets, mina hasta saldo positivo
#   - Uso:   envía 20 BTC, inspecciona mempool, confirma, imprime detalles

set -e

# ============================================================
#  SETUP — Descargar, verificar e instalar Bitcoin Core
# ============================================================

BITCOIN_VERSION="29.0"
BITCOIN_ARCH="x86_64-linux-gnu"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
TARBALL="bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz"

echo "=== Setup ==="
echo "Descargando Bitcoin Core ${BITCOIN_VERSION}..."
cd /tmp
wget -q "${BITCOIN_URL}/${TARBALL}"
wget -q "${BITCOIN_URL}/SHA256SUMS"
wget -q "${BITCOIN_URL}/SHA256SUMS.asc"

echo "Verificando checksum SHA256..."
sha256sum --check SHA256SUMS --ignore-missing

echo "Importando claves de firma y verificando GPG..."
gpg --keyserver hkps://keys.openpgp.org --recv-keys \
    152812300785C96444D3334D17565732E08E5E41 2>/dev/null || true
gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep -E "Good signature|gpg:" || true
echo ""
echo "Verificación exitosa de la firma binaria"

echo "Extrayendo e instalando binarios..."
tar -xzf "${TARBALL}"
sudo cp "bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
bitcoind --version | head -1

# ============================================================
#  INIT — Configurar regtest, crear wallets, minar
# ============================================================

echo ""
echo "=== Init ==="

mkdir -p ~/.bitcoin
cat > ~/.bitcoin/bitcoin.conf << 'CONF'
regtest=1
fallbackfee=0.0001
server=1
txindex=1
CONF

echo "Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 3

CLI="bitcoin-cli -regtest"

echo "Creando wallets Miner y Trader..."
$CLI createwallet "Miner" > /dev/null
$CLI createwallet "Trader" > /dev/null

MINER_ADDR=$($CLI -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "Dirección Miner (Recompensa de Mineria): $MINER_ADDR"

echo "Minando bloques hasta obtener saldo positivo..."
BLOCKS_NEEDED=0
while true; do
    BALANCE=$($CLI -rpcwallet=Miner getbalance)
    if [ "$(echo "$BALANCE > 0" | bc)" -eq 1 ]; then
        break
    fi
    $CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null
    BLOCKS_NEEDED=$((BLOCKS_NEEDED + 1))
done

echo "Bloques necesarios para saldo positivo: $BLOCKS_NEEDED"
echo ""
echo "# Las recompensas de coinbase requieren 100 confirmaciones para madurar."
echo "# El bloque 1 genera 50 BTC, pero esa UTXO no es gastable hasta que"
echo "# se minan 100 bloques más encima. En el bloque 101, la primera"
echo "# coinbase madura y el saldo pasa de 0 a 50 BTC."

MINER_BALANCE=$($CLI -rpcwallet=Miner getbalance)
echo ""
echo "Saldo billetera Miner: $MINER_BALANCE BTC"

# ============================================================
#  USO — Enviar 20 BTC, mempool, confirmar, detalles
# ============================================================

echo ""
echo "=== Uso ==="

TRADER_ADDR=$($CLI -rpcwallet=Trader getnewaddress "Recibido")
echo "Dirección Trader (Recibido): $TRADER_ADDR"

TXID=$($CLI -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)
echo "Tx enviada — txid: $TXID"

echo ""
echo "--- Transacción no confirmada en mempool ---"
$CLI getmempoolentry "$TXID" | jq .

echo ""
echo "Confirmando transacción (minando 1 bloque)..."
$CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

RAW=$($CLI getrawtransaction "$TXID" true)

# Calcular suma de entradas mirando cada vin
INPUT_SUM=0
for row in $(echo "$RAW" | jq -c '.vin[]'); do
    PREV_TXID=$(echo "$row" | jq -r '.txid')
    PREV_VOUT=$(echo "$row" | jq -r '.vout')
    PREV_TX=$($CLI getrawtransaction "$PREV_TXID" true)
    PREV_AMOUNT=$(echo "$PREV_TX" | jq ".vout[$PREV_VOUT].value")
    INPUT_SUM=$(echo "$INPUT_SUM + $PREV_AMOUNT" | bc)
done

INPUT_ADDR=$(echo "$RAW" | jq -r '.vin[0].txid' | xargs -I{} $CLI getrawtransaction {} true | \
    jq -r ".vout[$(echo "$RAW" | jq -r '.vin[0].vout')].scriptPubKey.address")

SENT_AMOUNT=$(echo "$RAW" | jq -r \
    "[.vout[] | select(.scriptPubKey.address == \"$TRADER_ADDR\")] | .[0].value")
CHANGE_ADDR=$(echo "$RAW" | jq -r \
    "[.vout[] | select(.scriptPubKey.address != \"$TRADER_ADDR\")] | .[0].scriptPubKey.address")
CHANGE_AMOUNT=$(echo "$RAW" | jq -r \
    "[.vout[] | select(.scriptPubKey.address != \"$TRADER_ADDR\")] | .[0].value")

OUTPUT_SUM=$(echo "$RAW" | jq '[.vout[].value] | add')
FEE=$(echo "$INPUT_SUM - $OUTPUT_SUM" | bc)

BLOCKHASH=$(echo "$RAW" | jq -r '.blockhash')
BLOCK_HEIGHT=$($CLI getblock "$BLOCKHASH" | jq '.height')

MINER_FINAL=$($CLI -rpcwallet=Miner getbalance)
TRADER_FINAL=$($CLI -rpcwallet=Trader getbalance)

echo ""
echo "--- Detalles de la transacción ---"
echo "txid: $TXID"
echo "$INPUT_ADDR: $INPUT_SUM BTC, Cantidad de entrada."
echo "$TRADER_ADDR: $SENT_AMOUNT BTC, Cantidad enviada."
echo "$CHANGE_ADDR: $CHANGE_AMOUNT BTC, Cantidad de cambio."
echo "Comisiones: $FEE BTC"
echo "Bloque: $BLOCK_HEIGHT"
echo "Saldo de Miner: $MINER_FINAL BTC"
echo "Saldo de Trader: $TRADER_FINAL BTC"
