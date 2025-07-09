#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# semana1-pro.sh - Bitcoin Core Week 1 Automation Script
#
# Este script automatiza los pasos del ejercicio de la Semana 1
#   * Descarga e instalación de Bitcoin Core
#   * Verificación SHA‑256 y firma GPG
#   * Configuración básica de regtest
#   * Arranque de bitcoind y creación de wallets
#   * Minado hasta balance positivo
#   * Envío de 20 BTC de Miner a Trader y detalles de la transacción
#
# Requisitos:
#   - wget, gpg, sha256sum, jq
#   - Permisos de escritura en /usr/local/bin (usa sudo si está disponible)
#
# Variables de entorno opcionales:
#   BITCOIN_VERSION    Versión de Bitcoin Core a instalar (default: 29.0)
#   DATADIR            Directorio de datos (default: ~/.bitcoin)
# ---------------------------------------------------------------------------

BITCOIN_VERSION=${BITCOIN_VERSION:-29.0}
DATADIR=${DATADIR:-$HOME/.bitcoin}

DEPENDENCIES=(wget gpg sha256sum jq)
for dep in "${DEPENDENCIES[@]}"; do
  command -v "$dep" >/dev/null 2>&1 || { echo "Falta dependencia: $dep"; exit 1; }
done

# Selección de arquitectura
case "$(uname -m)" in
  x86_64|amd64)  PLATFORM="x86_64-linux-gnu" ;;
  aarch64|arm64) PLATFORM="aarch64-linux-gnu" ;;
  *) echo "Arquitectura no soportada"; exit 1 ;;
esac

TAR="bitcoin-${BITCOIN_VERSION}-${PLATFORM}.tar.gz"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
SHA_FILE="SHA256SUMS"
SIG_FILE="${SHA_FILE}.asc"
TMPDIR=$(mktemp -d)

echo "📥 Descargando Bitcoin Core $BITCOIN_VERSION…"
wget -q -P "$TMPDIR" "$BASE_URL/$TAR" "$BASE_URL/$SHA_FILE" "$BASE_URL/$SIG_FILE"

echo "🔑 Importando claves de confianza…"
wget -q -O "$TMPDIR/trusted-keys" \
  https://raw.githubusercontent.com/bitcoin/bitcoin/master/contrib/verify-commits/trusted-keys
gpg --import "$TMPDIR/trusted-keys" >/dev/null

echo "🖋️ Verificando firma de SHA256SUMS…"
gpg --verify "$TMPDIR/$SIG_FILE" "$TMPDIR/$SHA_FILE"
echo "Binary signature verification successful"

echo "🔒 Verificando hash del tarball…"
grep "$TAR" "$TMPDIR/$SHA_FILE" | sha256sum --check -

echo "📂 Extrayendo e instalando binarios…"
tar -xf "$TMPDIR/$TAR" -C "$TMPDIR"
if command -v sudo >/dev/null 2>&1; then SUDO=sudo; else SUDO=""; fi
$SUDO install -m 0755 "$TMPDIR/bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/

echo "⚙️ Configurando directorio de datos en $DATADIR"
mkdir -p "$DATADIR"
CONF="$DATADIR/bitcoin.conf"
if [[ ! -f "$CONF" ]]; then
  cat > "$CONF" <<EOF
regtest=1
server=1
txindex=1
fallbackfee=0.0002
EOF
fi

echo "🚀 Arrancando bitcoind (regtest)…"
if ! bitcoin-cli -datadir="$DATADIR" -regtest getblockchaininfo >/dev/null 2>&1; then
  bitcoind -datadir="$DATADIR" -daemon
  echo -n "⏳ Esperando RPC"
  until bitcoin-cli -datadir="$DATADIR" -regtest getblockchaininfo >/dev/null 2>&1; do
    echo -n "."; sleep 1
  done
  echo " listo!"
fi

# Creación de wallets
for WALLET in Miner Trader; do
  bitcoin-cli -datadir="$DATADIR" -regtest createwallet "$WALLET" 2>/dev/null || true
done

# Dirección del minero
MINER_ADDR=$(bitcoin-cli -datadir="$DATADIR" -regtest -rpcwallet=Miner getnewaddress "Miner coinbase" bech32)

echo "⛏️ Minando hasta balance positivo…"
BLOCKS=0
while [[ "$(bitcoin-cli -datadir="$DATADIR" -regtest -rpcwallet=Miner getbalance)" == "0.00000000" ]]; do
  bitcoin-cli -datadir="$DATADIR" -regtest generatetoaddress 1 "$MINER_ADDR" >/dev/null
  ((BLOCKS++))
done
echo "🔢 Bloques minados: $BLOCKS"

# Envío de 20 BTC
TRADER_ADDR=$(bitcoin-cli -datadir="$DATADIR" -regtest -rpcwallet=Trader getnewaddress "Trader receive" bech32)
TXID=$(bitcoin-cli -datadir="$DATADIR" -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20 "" "pago a Trader")
echo "💸 TX enviada: $TXID"

echo "📋 Entrada en mempool:"
bitcoin-cli -datadir="$DATADIR" -regtest getmempoolentry "$TXID"

# Confirmación
bitcoin-cli -datadir="$DATADIR" -regtest generatetoaddress 1 "$MINER_ADDR" >/dev/null
echo "✅ TX confirmada en el bloque actual"

# Detalles y métricas
TX_DETAIL=$(bitcoin-cli -datadir="$DATADIR" -regtest gettransaction "$TXID" true)
FEE=$(echo "$TX_DETAIL" | jq '.fee | abs')
CHANGE=$(echo "$TX_DETAIL" | jq '[.details[] | select(.category=="send" and .internal==true) | .amount] | add | abs')
echo -e "Resumen de la transacción:\n  Tarifa: ${FEE} BTC\n  Cambio: ${CHANGE} BTC"

# Parada limpia (útil en CI)
bitcoin-cli -datadir="$DATADIR" -regtest stop >/dev/null
echo "🧹 bitcoind detenido. Script completado con éxito."
