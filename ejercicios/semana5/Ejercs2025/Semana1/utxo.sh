#!/bin/bash

: '
# Ejecuta el siguientes comando desde el directorio donde está el script (debes tener docker instalado y corriendo):

docker run -ti --platform linux/x86_64 \
  -v "$PWD/utxo.sh:/opt/utxo.sh" \
  ubuntu:latest bash -c "apt-get update && apt-get install -y wget gpg git nano jq bc && bash /opt/utxo.sh; exec bash"
' 

set -e

BITCOIN_VERSION="29.0"
TARFILE="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
WORKDIR="/opt/bitcoin"

log() {
    echo -e "$1"
}

instalar_dependencias() {
    log "🔧 Instalando paquetes requeridos..."
    apt-get update && apt-get install -y wget gpg git nano jq bc
}

crear_directorio_trabajo() {
    log "📁 Creando directorio de trabajo en ${WORKDIR}..."
    mkdir -p "$WORKDIR"
    cd "$WORKDIR"
}

crear_configuracion_bitcoin() {
    log "📝 Creando configuración de Bitcoin..."
    mkdir -p /root/.bitcoin
    cat > /root/.bitcoin/bitcoin.conf << 'EOF'
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=satoshi
rpcpassword=satoshi
EOF
}

descargar_archivos() {
    log "⬇️ Verificando si los archivos a descargar ya existen, si no los descargamos..."
    if [ -f "$TARFILE" ]; then
        log "📂 $TARFILE ya existe — omitiendo descarga."
    else
        log "⬇️ Descargando $TARFILE..."
        wget -q --show-progress "${BASE_URL}/${TARFILE}"
    fi
    if [ -f "SHA256SUMS" ]; then
        log "📂 SHA256SUMS ya existe — omitiendo descarga."
    else
        log "⬇️ Descargando SHA256SUMS..."
        wget -q --show-progress "${BASE_URL}/SHA256SUMS"
    fi
    if [ -f "SHA256SUMS.asc" ]; then
        log "📂 SHA256SUMS.asc ya existe — omitiendo descarga."
    else
        log "⬇️ Descargando SHA256SUMS.asc..."
        wget -q --show-progress "${BASE_URL}/SHA256SUMS.asc"
    fi
}

verificar_checksum() {
    log "🔐 Verificando checksums SHA256..."
    if sha256sum --ignore-missing --check SHA256SUMS | grep -q "${TARFILE}: OK"; then
        log "✅ Checksum verificado: ${TARFILE}"
    else
        log "❌ Falló la verificación de checksum. Saliendo."
        exit 1
    fi
}

importar_claves_gpg() {
    log "🔑 Importando todas las claves GPG de desarrolladores..."
    if [ ! -d "guix.sigs" ]; then
        git clone -q https://github.com/bitcoin-core/guix.sigs
    else
        log "📂 El directorio guix.sigs ya existe — omitiendo clonación."
    fi
    gpg --import guix.sigs/builder-keys/*
}

verificar_firma() {
    log "🧾 Verificando firma en SHA256SUMS.asc..."
    if ! gpg --verify SHA256SUMS.asc 2>&1 | grep -q "Good signature from"; then
        log "❌ Falló la verificación de firma GPG. Saliendo."
        exit 1
    fi

    log "🔍 Verificando integridad de archivo con SHA256SUMS..."
    if ! sha256sum --ignore-missing --check SHA256SUMS 2>&1 | grep -q ": OK"; then
        log "❌ Falló la verificación de checksum SHA256. Saliendo."
        exit 1
    fi

    log "✅ Verificación exitosa de la firma binaria"
}

extraer_bitcoin() {
    log "📦 Extrayendo Bitcoin Core..."
    tar -xzf "$TARFILE"
}

crear_enlaces_simbolicos() {
    log "🔗 Creando enlaces simbólicos para herramientas CLI de Bitcoin..."
    ln -sf "$WORKDIR/bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/
}

iniciar_bitcoin_regtest() {
    log "🟢 Iniciando bitcoind en modo regtest..."
    bitcoind -daemon
    sleep 2
}

crear_billeteras() {
    log "💰 Creando billeteras Miner y Trader..."
    bitcoin-cli createwallet "Miner"
    bitcoin-cli createwallet "Trader"
}

crear_direccion_recompensa_mineria() {
    log "📍 Creando dirección de recompensa de minería..."
    MINER_ADDR=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
    log "💰 Dirección de recompensa de minería creada: $MINER_ADDR"
}

minar() {
    log "⛏️ Iniciando proceso de mineria..."
    BLOCKS=0
    BALANCE=0
    while [ "$(bitcoin-cli -rpcwallet=Miner getbalance)" = "0.00000000" ]; do
        bitcoin-cli generatetoaddress 1 "$MINER_ADDR"
        BLOCKS=$((BLOCKS + 1))
        log "⛏️ Bloques minados: $BLOCKS"
    done
    
    log "⛏️ Se minaron $BLOCKS bloques debido a que las transacciones coinbase tienen un timelock de 100 bloques para evitar gastarlo inmediatamente por si hubiese algún re-org"
    log "💰 El saldo de la billetera Miner es de $(bitcoin-cli -rpcwallet=Miner getbalance) BTC"
}

crear_direccion_receptora() {
    log "📍 Creando dirección receptora..."
    TRADER_ADDR=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido")
    log "💰 Dirección dreceptora creada: $TRADER_ADDR"
}

enviar_tx() {
    log "📍 Enviando 20 BTC desde Miner a Trader..."
    TXID=$(bitcoin-cli -rpcwallet=Miner send '{"'$TRADER_ADDR'": 20}' | jq -r '.txid')
    log "➡️ Transaccion enviada. TXID: $TXID"
}

obtener_tx_del_mempool() {
    log "📍 Obteniendo transaccion del mempool..."
    TX=$(bitcoin-cli getmempoolentry $TXID)
}

confirmar_tx() {
    log "📍 Confirmando transaccion... (minando un bloque más)"
    TX_HEX=$(bitcoin-cli generatetoaddress 1 "$MINER_ADDR" | jq -r '.[]')
}

obtener_tx_minada() {
    RAW_TX=$(bitcoin-cli getrawtransaction $TXID)
    DECODED_TX=$(bitcoin-cli decoderawtransaction $RAW_TX)

    echo "=========================================================="
    echo "Imprimiendo por pantalla los detalles de la transacción..."
    
    # txid: <ID de la transacción>
    echo "txid: $(echo $DECODED_TX | jq -r '.txid')"
    
    # <Desde, Cantidad>: <Dirección del Miner>, Cantidad de entrada.
    PREV_TX=$(bitcoin-cli -rpcwallet=Miner gettransaction $(echo $DECODED_TX | jq -r '.vin[0].txid'))
    INPUT=$(echo $PREV_TX | jq -r '.details[0].amount')
    echo "<Desde:  $(echo $PREV_TX | jq -r '.details[0].address'), Cantidad: $INPUT)>"

    # <Enviar, Cantidad>: <Dirección del Trader>, Cantidad enviada.
    OUTPUT1=$(echo $DECODED_TX | jq -r '.vout[1].value')
    echo "<Enviar: $(echo $DECODED_TX | jq -r '.vout[1].scriptPubKey.address'), Cantidad: $OUTPUT1>"

    # <Cambio, Cantidad>: <Dirección del Miner>, Cantidad de cambio.
    OUTPUT2=$(echo $DECODED_TX | jq -r '.vout[0].value')
    echo "<Cambio: $(echo $DECODED_TX | jq -r '.vout[0].scriptPubKey.address'), Cantidad: $OUTPUT2>"

    # Comisiones: Cantidad pagada en comisiones.
    COMISIONES=$(echo "$INPUT - $OUTPUT1 - $OUTPUT2" | bc -l)
    echo "Comisions: $COMISIONES"

    # Bloque: Altura del bloque en el que se confirmó la transacción.
    RAW_TX_VERBOSE=$(bitcoin-cli getrawtransaction $TXID true)
    BLOCKHASH=$(echo $RAW_TX_VERBOSE | jq -r '.blockhash')
    HEIGHT=$(bitcoin-cli getblock $BLOCKHASH | jq -r '.height')
    echo "Bloque: $HEIGHT"

    # Saldo de Miner: Saldo de la billetera Miner después de la transacción.
    SALDO_MINER=$(bitcoin-cli -rpcwallet=Miner getbalance)
    echo "Saldo de Miner: $SALDO_MINER BTC"

    # Saldo de Trader: Saldo de la billetera Trader después de la transacción.
    SALDO_TRADER=$(bitcoin-cli -rpcwallet=Trader getbalance)
    echo "Saldo de Trader: $SALDO_TRADER BTC"
}

parar_bitcoin_core() {
    log "⛔️ parando el servicio de Bitcoin Core..."
    bitcoin-cli stop

}

main() {
    log "🚀 Iniciando instalación de Bitcoin Core con verificación..."
    instalar_dependencias
    crear_directorio_trabajo
    crear_configuracion_bitcoin
    descargar_archivos
    verificar_checksum
    importar_claves_gpg
    verificar_firma
    extraer_bitcoin
    crear_enlaces_simbolicos
    iniciar_bitcoin_regtest
    crear_billeteras
    crear_direccion_recompensa_mineria
    minar
    crear_direccion_receptora
    enviar_tx
    obtener_tx_del_mempool
    confirmar_tx
    obtener_tx_minada
    parar_bitcoin_core
    log "✅ Fin del Ejercicio!"
}

main