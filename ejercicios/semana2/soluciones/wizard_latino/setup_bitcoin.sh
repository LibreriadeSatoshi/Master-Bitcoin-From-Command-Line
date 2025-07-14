#!/bin/bash

# =============================================================================
# MÓDULO: Setup Bitcoin Core
# =============================================================================
# Taller: Master Bitcoin From Command Line
# Librería de Satoshi
# Autor: wizard_latino
#
# Descripción: Módulo reutilizable para configurar Bitcoin Core
# - Verifica/descarga binarios de Bitcoin Core
# - Configura entorno RPC
# - Inicia bitcoind en modo regtest
# Uso: source setup_bitcoin.sh

# Variables globales para el módulo
BITCOIN_VERSION="29.0"
BITCOIN_TOOLS_DIR="${HOME}/bitcoin-tools"
BITCOIN_BIN_DIR="${BITCOIN_TOOLS_DIR}/bin"
BITCOIN_DOWNLOADS_DIR="${BITCOIN_TOOLS_DIR}/downloads"

# Función para verificar binarios
check_binaries() {
    print_separator
    echo -e "${CYAN}Paso 1: Verificar binarios de Bitcoin Core${NC}"
    echo -e "${YELLOW}Se espera: Confirmar que los binarios están disponibles o descargarlos automáticamente${NC}"
    
    if [ ! -f "${BITCOIN_BIN_DIR}/bitcoind" ] || [ ! -f "${BITCOIN_BIN_DIR}/bitcoin-cli" ]; then
        echo -e "${YELLOW}Binarios no encontrados. Procediendo con descarga automática...${NC}"
        download_bitcoin_core
    else
        echo -e "${GREEN}✓ Binarios encontrados en: ${BITCOIN_BIN_DIR}/${NC}"
        echo -e "${GREEN}✓ bitcoind y bitcoin-cli ya están disponibles${NC}"
    fi
}

# Función para descargar Bitcoin Core (extraída de semana1)
download_bitcoin_core() {
    print_separator
    echo -e "${CYAN}Paso 1.1: Descargar Bitcoin Core ${BITCOIN_VERSION}${NC}"
    echo -e "${YELLOW}Se espera: Descarga automática de binarios oficiales con verificación criptográfica${NC}"
    
    # Variables de descarga
    BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
    BITCOIN_TAR="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
    GUIX_SIGS_URL="https://github.com/bitcoin-core/guix.sigs.git"
    
    # Crear directorio de descarga
    mkdir -p "${BITCOIN_DOWNLOADS_DIR}"
    cd "${BITCOIN_DOWNLOADS_DIR}" || { echo -e "${RED}Error: No se pudo acceder a ${BITCOIN_DOWNLOADS_DIR}${NC}"; exit 1; }
    
    # Descargar archivos
    print_separator
    echo -e "${CYAN}Paso 1.2: Descargar archivos de Bitcoin Core${NC}"
    echo -e "${YELLOW}Se espera: Descarga de binarios, checksums y firmas criptográficas${NC}"
    
    # Verificar si ya existen archivos de descarga
    if [ -f "${BITCOIN_TAR}" ] && [ -f "SHA256SUMS" ] && [ -f "SHA256SUMS.asc" ]; then
        echo -e "${GREEN}✓ Archivos ya descargados previamente${NC}"
    else
        echo -e "${YELLOW}Descargando binarios principales (~50MB)...${NC}"
        # Usar wget con progreso visible nativo
        wget --progress=bar -O "${BITCOIN_TAR}" "${BITCOIN_URL}"
        echo -e "${GREEN}✓ Descarga completada${NC}"
        echo -e "${YELLOW}Descargando checksums SHA256...${NC}"
        wget -q -O SHA256SUMS "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
        echo -e "${YELLOW}Descargando firmas criptográficas...${NC}"
        wget -q -O SHA256SUMS.asc "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc"
        echo -e "${GREEN}✓ Archivos descargados correctamente${NC}"
    fi
    
    # Verificar checksums
    print_separator
    echo -e "${CYAN}Paso 1.3: Verificar integridad criptográfica${NC}"
    echo -e "${YELLOW}Se espera: Validación SHA256 para garantizar integridad de archivos${NC}"
    
    CHECK_OUTPUT=$(sha256sum --ignore-missing --check SHA256SUMS 2>&1)
    if echo "${CHECK_OUTPUT}" | grep -q "${BITCOIN_TAR}: OK"; then
        echo -e "${GREEN}✓ Checksum SHA256 verificado correctamente${NC}"
        echo -e "${GREEN}✓ Integridad de archivos confirmada${NC}"
    else
        echo -e "${RED}Error: Fallo en la verificación de checksums${NC}"
        echo -e "${RED}Los archivos pueden estar corruptos o modificados${NC}"
        exit 1
    fi
    
    # Extraer binarios
    print_separator
    echo -e "${CYAN}Paso 1.4: Extraer binarios de Bitcoin Core${NC}"
    echo -e "${YELLOW}Se espera: Extracción e instalación de herramientas bitcoind y bitcoin-cli${NC}"
    
    # Crear directorio temporal para extracción
    local temp_extract_dir="${BITCOIN_DOWNLOADS_DIR}/temp_extract"
    mkdir -p "${temp_extract_dir}"
    tar -xzf "${BITCOIN_TAR}" -C "${temp_extract_dir}"
    
    # Mover solo los binarios a la ubicación final limpia
    mkdir -p "${BITCOIN_BIN_DIR}"
    mv "${temp_extract_dir}"/bitcoin-*/bin/* "${BITCOIN_BIN_DIR}/"
    
    # Limpiar directorio temporal
    rm -rf "${temp_extract_dir}"
    
    echo -e "${GREEN}✓ Binarios extraídos en: ${BITCOIN_BIN_DIR}${NC}"
    echo -e "${GREEN}✓ bitcoind y bitcoin-cli listos para usar${NC}"
    
    # Limpiar archivos de descarga
    cd - > /dev/null
    echo -e "${GREEN}Bitcoin Core ${BITCOIN_VERSION} instalado correctamente${NC}"
}

# Función para configurar entorno Bitcoin
setup_bitcoin_environment() {
    print_separator
    echo -e "${CYAN}Paso 2: Configurar entorno Bitcoin para usuario actual${NC}"
    echo -e "${YELLOW}Se espera: Crear archivo de configuración con credenciales RPC para modo regtest${NC}"
    
    # Crear directorio bitcoin para usuario actual
    mkdir -p "${HOME}/.bitcoin"
    
    # Crear configuración con RPC habilitado
    cat << EOF > "${HOME}/.bitcoin/bitcoin.conf"
regtest=1
fallbackfee=0.0001
server=1
txindex=1

[regtest]
rpcuser=bitcoinrpc
rpcpassword=bitcoinrpcpassword
rpcbind=127.0.0.1
rpcallowip=127.0.0.1
rpcport=18443
EOF
    
    echo -e "${GREEN}Archivo bitcoin.conf creado correctamente con configuración RPC${NC}"
}

# Función para iniciar bitcoind
start_bitcoind() {
    print_separator
    echo -e "${CYAN}Paso 3: Verificar o iniciar bitcoind${NC}"
    echo -e "${YELLOW}Se espera: Iniciar el nodo Bitcoin Core en modo regtest y establecer conexión RPC${NC}"
    
    # Detener cualquier bitcoind previo para evitar conflictos
    if pgrep bitcoind > /dev/null; then
        echo -e "${YELLOW}Deteniendo bitcoind previo para evitar conflictos...${NC}"
        ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest stop 2>/dev/null || pkill bitcoind
        sleep 3
    fi
    
    # Iniciar bitcoind en modo daemon
    echo -e "${YELLOW}Iniciando bitcoind en modo regtest...${NC}"
    ${BITCOIN_BIN_DIR}/bitcoind -daemon -regtest
    sleep 8
    
    # Verificar conectividad RPC con reintentos
    echo -e "${YELLOW}Verificando conectividad RPC...${NC}"
    for i in {1..10}; do
        if ${BITCOIN_BIN_DIR}/bitcoin-cli -regtest getblockchaininfo >/dev/null 2>&1; then
            echo -e "${GREEN}Conexión RPC establecida correctamente${NC}"
            echo -e "${GREEN}Nodo Bitcoin iniciado en modo regtest${NC}"
            return 0
        fi
        echo -e "${YELLOW}Esperando conexión RPC... (${i}/10)${NC}"
        sleep 2
    done
    
    echo -e "${RED}Error: No se pudo establecer conexión RPC${NC}"
    exit 1
}

# Función principal del módulo
setup_bitcoin_core() {
    echo -e "${CYAN}=== CONFIGURACIÓN DE BITCOIN CORE ===${NC}"
    check_binaries
    setup_bitcoin_environment
    start_bitcoind
    echo -e "${GREEN}✓ Bitcoin Core listo para usar${NC}"
}