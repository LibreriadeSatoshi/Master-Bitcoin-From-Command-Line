#!/bin/bash

################################################################################
# NOTA: Este archivo aunque fue inicialmente hecho manual, se ha pasado por IA
# para que sea más verboso y autoexplicativo así como más limipio
################################################################################

set -euo pipefail

# --- VARIABLES DE CONFIGURACIÓN ---
BITCOIN_VERSION="29.0"
BITCOIN_USER="bitcoin"
BITCOIN_DATA_DIR="/home/bitcoin"
BITCOIN_CONF_DIR="${BITCOIN_DATA_DIR}/.bitcoin"
BITCOIN_CONF_FILE="${BITCOIN_CONF_DIR}/bitcoin.conf"

# URLs
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
FILE_TAR="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
FILE_SUMS="SHA256SUMS"
FILE_SIGS="SHA256SUMS.asc"
GUIX_REPO="https://github.com/bitcoin-core/guix.sigs.git"

WORK_DIR=""

# --- ESTILOS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- ALIAS COMANDO ---
bcli() {
    sudo -u "${BITCOIN_USER}" bitcoin-cli -datadir="${BITCOIN_CONF_DIR}" -regtest "$@"
}

# --- LOGGING ---
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()  { echo -e "${GREEN}[OK]${NC}   $1"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $1"; }
error(){ echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# --- TRAP ---
cleanup() {
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

# ==============================================================================
# FASE 1: PREPARACIÓN E INSTALACIÓN
# ==============================================================================

preparar_entorno() {
    log "Fase 1: Preparando entorno..."
    sudo -v # Refrescar sudo
    sudo apt-get update -qq >/dev/null
    sudo apt-get install -y jq wget gpg git coreutils >/dev/null

    WORK_DIR=$(mktemp -d)
    
    if ! id "${BITCOIN_USER}" &>/dev/null; then
        log "Creando usuario de sistema ${BITCOIN_USER}..."
        sudo useradd -r -m -d "${BITCOIN_DATA_DIR}" -s /bin/bash "${BITCOIN_USER}"
    fi
    
    sudo mkdir -p "${BITCOIN_DATA_DIR}"
    sudo chown "${BITCOIN_USER}:${BITCOIN_USER}" "${BITCOIN_DATA_DIR}"
    sudo chmod 750 "${BITCOIN_DATA_DIR}"
}

descargar_archivos() {
    cd "${WORK_DIR}"
    log "Descargando Bitcoin Core v${BITCOIN_VERSION}..."
    wget -q --show-progress "${BASE_URL}/${FILE_TAR}"
    wget -q "${BASE_URL}/${FILE_SUMS}"
    wget -q "${BASE_URL}/${FILE_SIGS}"
}

importar_llaves_guix() {
    cd "${WORK_DIR}"
    log "Importando firmas (Guix)..."
    git clone --depth 1 "${GUIX_REPO}" guix.sigs --quiet
    
    export GNUPGHOME="${WORK_DIR}/gpg_keyring"
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"

    find "${WORK_DIR}/guix.sigs/builder-keys" -name "*.gpg" -print0 | \
    xargs -0 gpg --import --quiet 2>/dev/null || true
}

verificar_integridad() {
    cd "${WORK_DIR}"
    log "Verificando integridad criptográfica..."

    if grep "${FILE_TAR}" "${FILE_SUMS}" | sha256sum -c - --status; then
        ok "Hash SHA256 verificado."
    else
        error "Checksum incorrecto."
    fi

    if gpg --verify "${FILE_SIGS}" "${FILE_SUMS}" 2> verify_output.txt; then
         GOOD_SIGS=$(grep -c "Good signature" verify_output.txt || true)
         if [ "$GOOD_SIGS" -gt 0 ]; then
            echo -e "${GREEN}   [OK] Firmas GPG válidas: $GOOD_SIGS${NC}"
         else
            error "Firmas GPG no confiables."
         fi
    else
        error "Firma del archivo SHA256SUMS inválida."
    fi
}

instalar_binarios() {
    cd "${WORK_DIR}"
    log "Instalando binarios..."
    tar -xzf "${FILE_TAR}"
    
    local SOURCE_BIN_DIR="${WORK_DIR}/bitcoin-${BITCOIN_VERSION}/bin"
    if [ ! -d "${SOURCE_BIN_DIR}" ]; then
         SOURCE_BIN_DIR=$(find "${WORK_DIR}" -type f -name "bitcoind" -printf "%h" | head -n 1)
    fi

    local BINARIOS=("bitcoind" "bitcoin-cli" "bitcoin-tx" "bitcoin-wallet" "bitcoin-util")
    for binario in "${BINARIOS[@]}"; do
        if [ -f "${SOURCE_BIN_DIR}/${binario}" ]; then
            sudo install -m 755 -o root -g root "${SOURCE_BIN_DIR}/${binario}" "/usr/local/bin/${binario}"
        fi
    done
    ok "Binarios instalados en /usr/local/bin"
}

# ==============================================================================
# FASE 2: CONFIGURACIÓN Y ARRANQUE
# ==============================================================================

configurar_nodo() {
    log "Fase 2: Configurando nodo..."
    
    if [ ! -d "${BITCOIN_CONF_DIR}" ]; then
        sudo -u bitcoin mkdir -p "${BITCOIN_CONF_DIR}"
    fi

    sudo -u bitcoin tee "${BITCOIN_CONF_FILE}" > /dev/null <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF
    sudo -u bitcoin chmod 600 "${BITCOIN_CONF_FILE}"
    ok "bitcoin.conf generado."
}

iniciar_demonio() {
    log "Gestionando proceso bitcoind..."
    
    # 1. PARADA LIMPIA
    if pgrep -x "bitcoind" > /dev/null; then
        warn "Deteniendo nodo existente..."
        # Usamos bcli para parar (más limpio)
        bcli stop >/dev/null 2>&1 || killall bitcoind
        sleep 2
    fi

    # 2. BORRADO DE DATOS (FRESH START)
    #if [ -d "${BITCOIN_CONF_DIR}/regtest" ]; then
        log "Borrando blockchain antigua (Regtest Reset)..."
        sudo rm -rf "${BITCOIN_CONF_DIR}/regtest"
    #fi

    # 3. ARRANQUE
    log "Iniciando nodo limpio..."
    # Aquí no usamos bcli porque es el demonio, no el cliente
    sudo -u bitcoin bitcoind -daemon -datadir="${BITCOIN_CONF_DIR}" > /dev/null

    # 4. ESPERA ACTIVA
    log "Esperando RPC..."
    local retries=0
    while ! bcli -rpcwait getblockchaininfo >/dev/null 2>&1; do
        sleep 1
        ((retries++))
        if [ $retries -gt 30 ]; then error "Timeout arranque bitcoind."; fi
        echo -n "."
    done
    echo ""
    ok "Nodo online (Blockchain vacía)."
}

# ==============================================================================
# FASE 3: MINERÍA Y WALLETS
# ==============================================================================

verificar_acceso() {
    if ! bcli getblockchaininfo >/dev/null 2>&1; then
        error "No hay conexión RPC."
    fi
}

crear_wallets() {
    log "Fase 3: Creando Wallets..."
    
    # Como hemos borrado 'regtest', sabemos que NO existen wallets.
    # Podemos crearlas directamente sin comprobaciones complejas.
    crear_simple() {
        local WNAME=$1
        if ! bcli -named createwallet wallet_name="$WNAME" ; then
        #if ! bcli -named createwallet wallet_name="$WNAME" >/dev/null 2>&1; then
            error "Fallo al crear wallet '$WNAME'."
        fi
        ok "Wallet '$WNAME' creada."
    }

    crear_simple "Miner"
    crear_simple "Trader"
}

minar_hasta_madurez() {
    log "Verificando fondos..."
    local MINER_ADDR=$(bcli -rpcwallet=Miner getnewaddress "Recompensa")
    
    # Check saldo gastable con JQ
    local BALANCES_JSON=$(bcli -rpcwallet=Miner getbalances)
    local NEED_TO_MINE=$(echo "$BALANCES_JSON" | jq -r 'if (.mine.trusted // 0) <= 0 then "true" else "false" end')
    local BLOCKS_MINED=0

    if [ "$NEED_TO_MINE" == "true" ]; then
        log "Saldo 0. Minando madurez (101 bloques)..."
        set +e
        while [ "$NEED_TO_MINE" == "true" ]; do
            # Usamos bcli
            if bcli generatetoaddress 1 "$MINER_ADDR" >/dev/null 2>&1; then
                ((BLOCKS_MINED++))
                if (( BLOCKS_MINED % 10 == 0 )); then echo -n "."; fi
            fi
            BALANCES_JSON=$(bcli -rpcwallet=Miner getbalances)
            NEED_TO_MINE=$(echo "$BALANCES_JSON" | jq -r 'if (.mine.trusted // 0) <= 0 then "true" else "false" end')
        done
        set -e
        echo ""
    else
        log "Saldo suficiente disponible."
    fi

    # Reporte
    BALANCES_JSON=$(bcli -rpcwallet=Miner getbalances)
    FINAL_TRUSTED=$(echo "$BALANCES_JSON" | jq -r '.mine.trusted // 0')
    FINAL_IMMATURE=$(echo "$BALANCES_JSON" | jq -r '.mine.immature // 0')
    
    echo "----------------------------------------------------------------"
    ok "ESTADO Billetera 'Miner'"
    LC_NUMERIC=C printf " Gastable:  ${GREEN}%.8f BTC${NC}\n" "$FINAL_TRUSTED"
    LC_NUMERIC=C printf " Inmaduro:  ${YELLOW}%.8f BTC${NC}\n" "$FINAL_IMMATURE"
    echo "----------------------------------------------------------------"
    echo
    echo "----------------------------------------------------------------"
    echo "El saldo de minería no aparece como 'Gastable' inmediatamente debido a la"
    echo "regla de consenso de 'Madurez de Coinbase' (Coinbase Maturity)."
    echo "Para proteger la red contra reorganizaciones (bloques huérfanos), las monedas"
    echo "recién minadas requieren 100 confirmaciones antes de poder gastarse."
    echo "Por eso minamos 101 bloques: 1 (Generación) + 100 (Confirmaciones)."
    echo "----------------------------------------------------------------"
}

# ==============================================================================
# FASE 4: TRANSACCIÓN
# ==============================================================================

ejecutar_ciclo_transaccion() {
    log "Fase 4: Ejecutando Transacción..."

    # 1. Preparación
    local TRADER_ADDR=$(bcli -rpcwallet=Trader getnewaddress "Recibido")
    log "Destino Trader: $TRADER_ADDR"

    # 2. Envío
    log "Enviando 20 BTC..."
    if ! TXID=$(bcli -rpcwallet=Miner sendtoaddress "$TRADER_ADDR" 20.0); then
        error "Fallo al enviar. Saldo insuficiente."
    fi
    ok "Enviado. TXID: $TXID"

    # 3. Mempool (FIX VISUAL: Formateo manual para evitar 1.41e-05)
    log "Inspeccionando Mempool..."
    local MEMPOOL_ENTRY=$(bcli getmempoolentry "$TXID")
    
    # Extraemos valores crudos
    local F_BASE=$(echo "$MEMPOOL_ENTRY" | jq -r '.fees.base')
    local WEIGHT=$(echo "$MEMPOOL_ENTRY" | jq -r '.weight')
    local HEIGHT=$(echo "$MEMPOOL_ENTRY" | jq -r '.height')

    # Construimos el JSON visualmente con printf para forzar 8 decimales
    echo "{"
    echo "  \"fees\": {"
    LC_NUMERIC=C printf "    \"base\": %.8f,\n" "$F_BASE"
    LC_NUMERIC=C printf "    \"modified\": %.8f,\n" "$F_BASE"
    LC_NUMERIC=C printf "    \"ancestor\": %.8f,\n" "$F_BASE"
    LC_NUMERIC=C printf "    \"descendant\": %.8f\n" "$F_BASE"
    echo "  },"
    echo "  \"weight\": $WEIGHT,"
    echo "  \"height\": $HEIGHT"
    echo "}"
    ok "Tx en Mempool."

    # 4. Confirmación
    log "Confirmando..."
    local CONFIRM_ADDR=$(bcli -rpcwallet=Miner getnewaddress "Confirm")
    bcli generatetoaddress 1 "$CONFIRM_ADDR" > /dev/null
    ok "Confirmada."

    # 5. Análisis Forense (FIX CRASH: Sin usar 'abs')
    log "Reporte forense..."
    local TX_JSON=$(bcli -rpcwallet=Miner gettransaction "$TXID" true true)

    # Cálculo manual de Fee (compatible con jq antiguo)
    local RAW_FEE=$(echo "$TX_JSON" | jq -r 'if .fee < 0 then .fee * -1 else .fee end')
    local FEE=$(LC_NUMERIC=C printf "%.8f" "$RAW_FEE")

    local BLOCK_HEIGHT=$(echo "$TX_JSON" | jq -r '.blockheight')
    
    # Extracción de Cambio
    local CHANGE_DATA=$(echo "$TX_JSON" | jq -r --arg TADDR "$TRADER_ADDR" \
        '.decoded.vout[] | select(.scriptPubKey.address != $TADDR) | "\(.scriptPubKey.address) \(.value)"')
    local CHANGE_ADDR=$(echo "$CHANGE_DATA" | awk '{print $1}')
    local CHANGE_AMOUNT=$(echo "$CHANGE_DATA" | awk '{print $2}')

    # Suma Total (Input)
    local RAW_INPUT=$(jq -n -r --arg sent "20.0" --arg change "$CHANGE_AMOUNT" --arg fee "$FEE" \
        '($sent | tonumber) + ($change | tonumber) + ($fee | tonumber)')
    local TOTAL_INPUT=$(LC_NUMERIC=C printf "%.8f" "$RAW_INPUT")

    local BAL_MINER=$(bcli -rpcwallet=Miner getbalance)
    local BAL_TRADER=$(bcli -rpcwallet=Trader getbalance)

    # 6. Reporte Final
    echo ""
    echo "======================================================================"
    echo -e "${CYAN}                  DETALLES DE LA TRANSACCIÓN                  ${NC}"
    echo "======================================================================"
    echo "txid: $TXID"
    echo "----------------------------------------------------------------------"
    LC_NUMERIC=C printf "<De, Cantidad>:     Miner Wallet, %s BTC\n" "$TOTAL_INPUT"
    LC_NUMERIC=C printf "<Enviar, Cantidad>: %s, %.8f BTC\n" "$TRADER_ADDR" 20.00000000
    LC_NUMERIC=C printf "<Cambio, Cantidad>: %s, %.8f BTC\n" "$CHANGE_ADDR" "$CHANGE_AMOUNT"
    LC_NUMERIC=C printf "Comisiones:         %s BTC\n" "$FEE"
    echo "Bloque Confirmado:  $BLOCK_HEIGHT"
    echo "----------------------------------------------------------------------"
    LC_NUMERIC=C printf "Saldo Final Miner:  %.8f BTC\n" "$BAL_MINER"
    LC_NUMERIC=C printf "Saldo Final Trader: %.8f BTC\n" "$BAL_TRADER"
    echo "======================================================================"
}

# ==============================================================================
# EJECUCIÓN
# ==============================================================================

preparar_entorno
descargar_archivos
importar_llaves_guix
verificar_integridad
instalar_binarios

configurar_nodo
iniciar_demonio

verificar_acceso
crear_wallets
minar_hasta_madurez

ejecutar_ciclo_transaccion
