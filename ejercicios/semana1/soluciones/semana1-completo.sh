#!/usr/bin/env bash
#
# -------------------------------------------------------------------
# Ejercicio Semana 1: Mastering Bitcoin From the Command Line
# Solución Completa y Automatizada
#
# Este script realiza todo el proceso:
# 1. Descarga y verifica criptográficamente los binarios de Bitcoin Core.
# 2. Instala los binarios en el sistema.
# 3. Configura e inicia un nodo en modo regtest.
# 4. Crea y financia wallets para simular una transacción.
# 5. Ejecuta una transacción y reporta los detalles.
# -------------------------------------------------------------------

set -euo pipefail

# --- SECCIÓN 1: CONFIGURACIÓN Y VERIFICACIÓN ---
echo "➡️ SECCIÓN 1: Configuración del nodo Bitcoin Core..."

# Variables para la versión de Bitcoin Core. Cambia la versión si es necesario.
BITCOIN_VERSION="29.0"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
TAR_FILE="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
SIGNER_KEY="01EA5486DE18A882D4C2684590C8019E36C2E964" # Clave GPG de Wladimir J. van der Laan

# 1. Descargar los binarios, hashes y firmas
echo "⬇️  Descargando Bitcoin Core v${BITCOIN_VERSION} (si es necesario)..."
if [ ! -f "$TAR_FILE" ]; then
    wget -q "${BITCOIN_URL}/${TAR_FILE}"
    wget -q "${BITCOIN_URL}/SHA256SUMS"
    wget -q "${BITCOIN_URL}/SHA256SUMS.asc"
    echo "✅ Descarga completa."
else
    echo "✅ Archivos de Bitcoin Core ya existen. Saltando descarga."
fi

# 2. Verificar la integridad de los archivos descargados
echo "🔎 Verificando la integridad criptográfica de los archivos..."
# Paso 2a: Verificar el hash del archivo
sha256sum --ignore-missing --check SHA256SUMS | grep "OK" || { echo "❌ Error: La verificación del hash SHA256 falló."; exit 1; }
echo "👍 Hash verificado correctamente."

# Paso 2b: Verificar la firma GPG del desarrollador
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$SIGNER_KEY" >/dev/null 2>&1
gpg --verify SHA256SUMS.asc SHA256SUMS 2>&1 | grep "Good signature" || { echo "❌ Error: La firma GPG es inválida. El binario no es confiable."; exit 1; }
echo "👍 Verificación exitosa de la firma binaria."

# 3. Instalar los binarios en una ubicación estándar
echo "⚙️  Instalando binarios en /usr/local/bin/..."
tar -xzf "$TAR_FILE"
sudo install -m 0755 -o root -g root -t /usr/local/bin "bitcoin-${BITCOIN_VERSION}/bin/*"
echo "✅ Binarios instalados con éxito."

# --- SECCIÓN 2: INICIO DEL NODO ---
echo -e "\n➡️ SECCIÓN 2: Inicio del nodo en modo regtest..."

# 1. Crear el directorio de datos y el archivo de configuración
BITCOIN_DIR="$HOME/.bitcoin"
mkdir -p "$BITCOIN_DIR"
cat > "$BITCOIN_DIR/bitcoin.conf" <<EOF
# Configuración para el modo regtest
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

# 2. Iniciar bitcoind como demonio (si no está corriendo)
if ! bitcoin-cli -regtest ping > /dev/null 2>&1; then
    bitcoind -daemon
    echo "🚀 Nodo iniciado. Esperando 5 segundos para que esté listo..."
    sleep 5
else
    echo "✅ El nodo bitcoind ya está en ejecución."
fi
bitcoin-cli -regtest getblockchaininfo > /dev/null # Un chequeo final para asegurar que el RPC está listo

# --- SECCIÓN 3: OPERACIONES CON WALLETS Y FONDOS ---
echo -e "\n➡️ SECCIÓN 3: Creando y financiando wallets..."

echo "👜 Creando wallets 'Miner' y 'Trader' (ignora error si ya existen)..."
bitcoin-cli -regtest createwallet "Miner" "" false false "" false true >/dev/null 2>&1 || true
bitcoin-cli -regtest createwallet "Trader" "" false false "" false true >/dev/null 2>&1 || true

# 4. Generar dirección y minar bloques para obtener recompensa
MINER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
echo "⛏️  Minando 101 bloques para madurar la recompensa inicial..."
bitcoin-cli -regtest generatetoaddress 101 "$MINER_ADDR" > /dev/null

# 5. Comentario sobre la madurez de la recompensa
echo -e "\n# Explicación: Se minan 101 bloques porque una recompensa de bloque (coinbase)"
echo "# necesita 100 confirmaciones adicionales para 'madurar' y poder ser gastada."
echo "# Bloque 1: genera la recompensa. Bloques 2-101: la confirman."

# 6. Imprimir saldo inicial del minero
MINER_INITIAL_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalance)
echo "💰 Saldo inicial de Miner: $MINER_INITIAL_BALANCE BTC"

# --- SECCIÓN 4: DEMOSTRACIÓN DE TRANSACCIÓN ---
echo -e "\n➡️ SECCIÓN 4: Realizando una transacción de Miner a Trader..."

# 1. Crear dirección en la wallet Trader
TRADER_ADDR=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Recibido")
echo "💸 Enviando 20 BTC desde Miner a la dirección de Trader: $TRADER_ADDR"
TXID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20)
echo "✔️ Transacción enviada. TXID: $TXID"

# 2. Mostrar la transacción en el mempool
echo "🕒 Transacción en el mempool:"
bitcoin-cli -regtest getmempoolentry "$TXID"

# 3. Confirmar la transacción minando 1 bloque más
echo "🔒 Confirmando la transacción con 1 bloque adicional..."
bitcoin-cli -regtest generatetoaddress 1 "$MINER_ADDR" >/dev/null

# --- SECCIÓN 5: REPORTE FINAL ---
echo -e "\n➡️ SECCIÓN 5: Detalles finales de la transacción confirmada..."

# 4. Obtener todos los detalles de la transacción usando jq
TX_DATA_VERBOSE=$(bitcoin-cli -regtest -rpcwallet=Miner gettransaction "$TXID" true)
RAW_TX=$(bitcoin-cli -regtest getrawtransaction "$TXID" true)

# Extraer detalles específicos
INPUT_AMOUNT=$(echo "$TX_DATA_VERBOSE" | jq -r '.amount | . * -1')
SENT_AMOUNT=$(echo "$TX_DATA_VERBOSE" | jq -r '.details[] | select(.category=="send") | .amount | . * -1')
CHANGE_AMOUNT=$(echo "$TX_DATA_VERBOSE" | jq -r '.details[] | select(.category=="receive" and .address != "'$MINER_ADDR'") | .amount') # Asumiendo que la dirección de cambio es nueva
FEES=$(echo "$TX_DATA_VERBOSE" | jq -r '.fee | . * -1')
BLOCK_HEIGHT=$(echo "$TX_DATA_VERBOSE" | jq -r '.blockheight')
INPUT_ADDRESS=$(bitcoin-cli -regtest getrawtransaction $(echo $RAW_TX | jq -r .vin[0].txid) true | jq -r ".vout[$(echo $RAW_TX | jq -r .vin[0].vout)].scriptPubKey.address")


# 5. Imprimir los detalles en el formato solicitado
echo "----------------------------------------------------"
echo "txid:           $TXID"
echo "<De, Cantidad>:   $INPUT_ADDRESS, $INPUT_AMOUNT BTC"
echo "<Enviar, Cantidad>: $TRADER_ADDR, $SENT_AMOUNT BTC"
echo "<Cambio, Cantidad>: (Nueva dirección de Miner), $CHANGE_AMOUNT BTC"
echo "Comisiones:     $FEES BTC"
echo "Bloque:         $BLOCK_HEIGHT"
echo "----------------------------------------------------"
echo "Saldo de Miner:   $(bitcoin-cli -regtest -rpcwallet=Miner getbalance) BTC"
echo "Saldo de Trader:  $(bitcoin-cli -regtest -rpcwallet=Trader getbalance) BTC"

echo -e "\n🎉 ¡Script completado con éxito!"