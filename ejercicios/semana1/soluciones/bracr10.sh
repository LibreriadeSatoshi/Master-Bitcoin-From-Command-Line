#!/bin/bash

echo "Verificando dependencias necesarias..."

# Función para instalar dependencias faltantes
install_if_missing() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 no está instalado. Instalando..."
    sudo apt update && sudo apt install -y "$2"
  else
    echo "$1 ya está instalado."
  fi
}

# Instalar dependencias
install_if_missing wget wget
install_if_missing gpg gnupg
install_if_missing git git
install_if_missing jq jq
install_if_missing bc bc

echo "Dependencias listas."

# Variables
DIR="bitcoin_core_temp_files"
URL_BASE="https://bitcoincore.org/bin/bitcoin-core-29.0"
FILE="bitcoin-29.0-x86_64-linux-gnu.tar.gz"

# Crear directorio y descargar archivos
mkdir -p "$DIR"
cd "$DIR" 

echo "Descargando Bitcoin Core..."
[ -f "$FILE" ] || wget "$URL_BASE/$FILE"
[ -f "SHA256SUMS" ] || wget "$URL_BASE/SHA256SUMS"
[ -f "SHA256SUMS.asc" ] || wget "$URL_BASE/SHA256SUMS.asc"

# Verificaciones
echo "Verificando SHA256..."
sha256sum --ignore-missing --check SHA256SUMS || { echo "Verificación SHA256 falló"; exit 1; }

echo "Verificando firmas PGP..."
[ -d "guix.sigs" ] || git clone https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/* >/dev/null 2>&1
gpg --verify SHA256SUMS.asc >/dev/null 2>&1 || { echo "Firma PGP inválida"; exit 1; }

echo "Verificación exitosa de la firma binaria"

# Extraer e instalar Bitcoin Core
echo "Instalando Bitcoin Core..."
tar xzf "$FILE"
sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*

cd ..
echo "Eliminando archivos de instalacion temporales" 
sudo rm -R $DIR

# Configurar Bitcoin
BITCOIN_DIR="$HOME/.bitcoin"
mkdir -p "$BITCOIN_DIR"

cat > "$BITCOIN_DIR/bitcoin.conf" << EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

echo "Configuración creada."

# Verificar si bitcoind está corriendo
if pgrep -f "bitcoind.*-regtest" >/dev/null 2>&1; then
  echo "bitcoind ya está ejecutándose."
else
  echo "Iniciando bitcoind en regtest..."
  rm -rf "$BITCOIN_DIR/regtest"  # Limpiar datos anteriores
  bitcoind -regtest -daemon
  sleep 5
fi

# Crear wallets
echo "Creando wallets..."
bitcoin-cli createwallet "Miner" >/dev/null 2>&1
bitcoin-cli createwallet "Trader" >/dev/null 2>&1
sleep 2
# Generar dirección y minar
echo "Generando dirección de minería..."
DIRECCION_RECOMPENSA=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")

echo "Minando bloques hasta obtener saldo..."
while (( $(echo "$(bitcoin-cli -rpcwallet=Miner getbalance) <= 0" | bc -l) )); do
  bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "$DIRECCION_RECOMPENSA" >/dev/null 2>&1
done

BLOQUES_NECESARIOS=$(bitcoin-cli getblockcount)
SALDO_MINER=$(bitcoin-cli -rpcwallet=Miner getbalance)

echo "Se necesitaron $BLOQUES_NECESARIOS bloques para obtener un saldo positivo"
echo "Saldo de Miner: $SALDO_MINER BTC"

# Crear transacción
echo "Creando transacción..."
DIRECCION_TRADER=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido")
TXID=$(bitcoin-cli -rpcwallet=Miner sendtoaddress "$DIRECCION_TRADER" 20)

echo "Transacción creada: $TXID"
echo "Estado del mempool:"
bitcoin-cli getmempoolentry "$TXID"

# Confirmar transacción
echo "Confirmando transacción..."
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "$DIRECCION_RECOMPENSA" >/dev/null 2>&1

# Obtener detalles de la transacción
RAW_TX=$(bitcoin-cli getrawtransaction "$TXID" true)

echo ""
echo "DETALLES DE LA TRANSACCION:"
echo "txid: $(echo "$RAW_TX" | jq -r '.txid')"

# Obtener información de entrada
PREV_TXID=$(echo "$RAW_TX" | jq -r '.vin[0].txid')
PREV_VOUT=$(echo "$RAW_TX" | jq -r '.vin[0].vout')
PREV_TX=$(bitcoin-cli getrawtransaction "$PREV_TXID" true)
INPUT_VALUE=$(echo "$PREV_TX" | jq -r ".vout[$PREV_VOUT].value")
INPUT_ADDRESS=$(echo "$PREV_TX" | jq -r ".vout[$PREV_VOUT].scriptPubKey.address")

echo "De: $INPUT_ADDRESS, Cantidad: $INPUT_VALUE BTC"

# Obtener información de salidas
echo "Enviar: $(echo "$RAW_TX" | jq -r '.vout[0].scriptPubKey.address'), $(echo "$RAW_TX" | jq -r '.vout[0].value') BTC"
echo "Cambio: $(echo "$RAW_TX" | jq -r '.vout[1].scriptPubKey.address'), $(echo "$RAW_TX" | jq -r '.vout[1].value') BTC"

# Calcular comisión
TOTAL_OUTPUT=$(echo "$RAW_TX" | jq '[.vout[].value] | add')
FEE=$(echo "$INPUT_VALUE - $TOTAL_OUTPUT" | bc)
echo "Comisiones: $FEE BTC"

# Información del bloque
BLOCK_HEIGHT=$(bitcoin-cli getblockcount)
echo "Bloque de confirmacion: $BLOCK_HEIGHT"

# Saldos finales
echo "Saldo de Miner: $(bitcoin-cli -rpcwallet=Miner getbalance) BTC"
echo "Saldo de Trader: $(bitcoin-cli -rpcwallet=Trader getbalance) BTC"