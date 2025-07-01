#!/bin/bash

# Script para el ejercicio de la Semana 1 - Master Bitcoin From Command Line
# Autor: wizard_latino
#
# Realiza la descarga, verificación, configuración,
# y uso de Bitcoin Core (versión 29.0) según las instrucciones descritas en el ejercicio de la Semana 1.
# https://github.com/LibreriadeSatoshi/Master-Bitcoin-From-Command-Line/blob/main/ejercicios/semana1/ejercicio.md
#
# Este script está diseñado para ejecutarse en un sistema Linux, específicamente en un contenedor
# Docker con Ubuntu donde el usuario es root (no usa comando sudo). 
# 
# Dependencias requeridas: wget, gnupg, tar, git, bc, jq
# Instrucciones para instalar dependencias en Ubuntu:
#   1. Actualiza los paquetes: apt update
#   2. Instala las dependencias: apt install -y wget gnupg tar git bc jq
#
# Los archivos descargados se guardan en $HOME/bitcoin_downloads y los binarios extraídos
# en $HOME/bitcoin_binaries. 

# Colores para la salida en consola
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color (reset)

# Variables
BITCOIN_VERSION="29.0"
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
BITCOIN_TAR="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
GUIX_SIGS_URL="https://github.com/bitcoin-core/guix.sigs.git"
DOWNLOAD_DIR="${HOME}/bitcoin_downloads"
EXTRACT_DIR="${HOME}/bitcoin_binaries"
BITCOIN_CONF="${HOME}/.bitcoin/bitcoin.conf"
MINER_WALLET="Miner"
TRADER_WALLET="Trader"
MINER_LABEL="Recompensa de Minería"
TRADER_LABEL="Recibido"

# Función para imprimir líneas separadoras
print_separator() {
    echo -e "${CYAN}----------------------------------------${NC}"
}

# === Sección de Configuración ===
print_separator
echo -e "${CYAN}===                                                                           ===${NC}"
echo -e "${CYAN}====== Configuración : Preparando y Verificando Descargas de Bitcoin Core  ======${NC}"
echo -e "${CYAN}===                                                                           ===${NC}"

# Paso 1: Verificar el directorio HOME
print_separator
echo -e "${CYAN}Paso 1: Verificar el directorio HOME${NC}"
echo -e "${YELLOW}Se espera: Confirmar que el directorio HOME está definido para guardar archivos${NC}"
if [ -z "${HOME}" ]; then
    echo -e "${RED}Error: No se encontró el directorio HOME${NC}"
    exit 1
fi
echo -e "${GREEN}Directorio HOME confirmado: ${HOME}${NC}"

# Paso 2: Crear directorio para descargas
print_separator
echo -e "${CYAN}Paso 2: Crear directorio para descargas${NC}"
echo -e "${YELLOW}Se espera: Crear el directorio ${DOWNLOAD_DIR} para almacenar archivos descargados${NC}"
mkdir -p "${DOWNLOAD_DIR}"
cd "${DOWNLOAD_DIR}" || { echo -e "${RED}Error: No se pudo acceder a ${DOWNLOAD_DIR}${NC}"; exit 1; }
echo -e "${GREEN}Directorio creado: ${DOWNLOAD_DIR}${NC}"

# Paso 3: Descargar binarios, checksums y firmas
print_separator
echo -e "${CYAN}Paso 3: Descargar binarios de Bitcoin Core ${BITCOIN_VERSION}${NC}"
echo -e "${YELLOW}Se espera: Descargar el archivo tar.gz, SHA256SUMS y SHA256SUMS.asc${NC}"
wget -O "${BITCOIN_TAR}" "${BITCOIN_URL}"
wget -O SHA256SUMS "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
wget -O SHA256SUMS.asc "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc"
echo -e "${GREEN}Archivos descargados: ${BITCOIN_TAR}, SHA256SUMS, SHA256SUMS.asc${NC}"

# Paso 4: Importar claves GPG
print_separator
echo -e "${CYAN}Paso 4: Importar claves GPG para verificación${NC}"
echo -e "${YELLOW}Se espera: Clonar el repositorio guix.sigs e importar las claves públicas${NC}"
git clone "${GUIX_SIGS_URL}"
if [ -d "guix.sigs/builder-keys" ]; then
    gpg --import guix.sigs/builder-keys/*
    echo -e "${GREEN}Claves GPG importadas correctamente${NC}"
    rm -rf guix.sigs
else
    echo -e "${RED}Error: No se pudo clonar guix.sigs o encontrar claves${NC}"
    exit 1
fi

# Paso 5: Verificar checksums
print_separator
echo -e "${CYAN}Paso 5: Verificar checksums de los binarios${NC}"
echo -e "${YELLOW}Se espera: Confirmar que el archivo ${BITCOIN_TAR} coincide con SHA256SUMS${NC}"
CHECK_OUTPUT=$(sha256sum --ignore-missing --check SHA256SUMS 2>&1)
echo "${CHECK_OUTPUT}"
if echo "${CHECK_OUTPUT}" | grep -q "${BITCOIN_TAR}: OK"; then
    echo -e "${GREEN}Checksum verificado correctamente${NC}"
else
    echo -e "${RED}Error: Fallo en la verificación de checksums${NC}"
    exit 1
fi

# Paso 6: Verificar firmas PGP
print_separator
echo -e "${CYAN}Paso 6: Verificar firmas PGP${NC}"
echo -e "${YELLOW}Se espera: Confirmar que SHA256SUMS.asc está firmado por claves confiables${NC}"
GPG_OUTPUT=$(gpg --verify SHA256SUMS.asc 2>&1)
echo "${GPG_OUTPUT}"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Verificación exitosa de la firma binaria${NC}"
else
    echo -e "${RED}Error: Fallo en la verificación de firmas PGP${NC}"
    exit 1
fi

# Paso 7: Extraer binarios
print_separator
echo -e "${CYAN}Paso 7: Extraer binarios de Bitcoin Core${NC}"
echo -e "${YELLOW}Se espera: Extraer los binarios a ${EXTRACT_DIR}${NC}"
mkdir -p "${EXTRACT_DIR}"
tar -xzf "${BITCOIN_TAR}" -C "${EXTRACT_DIR}" --strip-components=1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Binarios extraídos en: ${EXTRACT_DIR}${NC}"
    echo -e "${CYAN}Contenido del directorio bin:${NC}"
    ls -la "${EXTRACT_DIR}/bin/"
else
    echo -e "${RED}Error: Fallo al extraer los binarios${NC}"
    exit 1
fi

# === Sección de Inicio ===

print_separator
echo -e "${CYAN}===                                                                 ===${NC}"
echo -e "${CYAN}====== Inicio : Configurando e Iniciando Minado en Bitcoin Core  ======${NC}"
echo -e "${CYAN}===                                                                 ===${NC}"

# Paso 8: Crear archivo de configuración
print_separator
echo -e "${CYAN}Paso 8: Preparar el archivo de configuración de Bitcoin Core${NC}"
echo -e "${YELLOW}Se espera: Crear el archivo ${BITCOIN_CONF} con ajustes para regtest${NC}"
mkdir -p "${HOME}/.bitcoin"
cat << EOF > "${BITCOIN_CONF}"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF
echo -e "${GREEN}Archivo ${BITCOIN_CONF} creado correctamente${NC}"

# Paso 9: Iniciar bitcoind
print_separator
echo -e "${CYAN}Paso 9: Iniciar el nodo de Bitcoin Core en modo regtest${NC}"
echo -e "${YELLOW}Se espera: Iniciar bitcoind en segundo plano${NC}"
${EXTRACT_DIR}/bin/bitcoind -daemon
sleep 5 # Esperar a que bitcoind inicie
if pgrep bitcoind > /dev/null; then
    echo -e "${GREEN}Nodo iniciado correctamente${NC}"
else
    echo -e "${RED}Error: No se pudo iniciar el nodo${NC}"
    exit 1
fi

# Paso 10: Crear billeteras Miner y Trader
print_separator
echo -e "${CYAN}Paso 10: Crear las billeteras Miner y Trader${NC}"
echo -e "${YELLOW}Se espera: Generar las billeteras Miner y Trader${NC}"
${EXTRACT_DIR}/bin/bitcoin-cli createwallet "${MINER_WALLET}"
${EXTRACT_DIR}/bin/bitcoin-cli createwallet "${TRADER_WALLET}"
echo -e "${GREEN}Billeteras creadas correctamente${NC}"

# Paso 11: Generar dirección para Miner
print_separator
echo -e "${CYAN}Paso 11: Generar dirección para la billetera Miner${NC}"
echo -e "${YELLOW}Se espera: Crear una dirección con la etiqueta '${MINER_LABEL}'${NC}"
MINER_ADDRESS=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} getnewaddress "${MINER_LABEL}")
echo -e "${GREEN}Dirección creada (${MINER_LABEL}): ${MINER_ADDRESS}${NC}"
echo -e "${YELLOW}Verificando la etiqueta '${MINER_LABEL}'...${NC}"
LABELS_MINER=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} listlabels)
if echo "${LABELS_MINER}" | grep -q "${MINER_LABEL}"; then
    echo -e "${GREEN}Etiqueta '${MINER_LABEL}' confirmada${NC}"
else
    echo -e "${RED}Error: Etiqueta '${MINER_LABEL}' no encontrada${NC}"
    exit 1
fi

# Paso 12: Minar bloques para saldo positivo
print_separator
echo -e "${CYAN}Paso 12: Minar bloques para la billetera Miner${NC}"
echo -e "${YELLOW}Se espera: Minar al menos 101 bloques para obtener un saldo positivo${NC}"
BLOCKS_MINED=0
BALANCE=0
while [ $(echo "${BALANCE} <= 0" | bc) -eq 1 ]; do
    ${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} generatetoaddress 1 "${MINER_ADDRESS}" > /dev/null
    ((BLOCKS_MINED++))
    BALANCE=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} getbalance)
done
echo -e "${GREEN}Saldo positivo alcanzado tras minar ${BLOCKS_MINED} bloques${NC}"
echo -e "${YELLOW}Nota:${NC} El saldo inicial es 0 porque las recompensas de bloque requieren 100 confirmaciones para ser gastables. Se minan al menos 101 bloques para activar la primera recompensa."

# Paso 13: Mostrar saldo de Miner
print_separator
echo -e "${CYAN}Paso 13: Consultar saldo de la billetera Miner${NC}"
echo -e "${YELLOW}Se espera: Mostrar el saldo disponible en la billetera Miner${NC}"
echo -e "${GREEN}Saldo de la billetera Miner (${MINER_LABEL}): ${BALANCE} BTC${NC}"

# === Sección de Uso ===

print_separator
echo -e "${CYAN}===                                                     ===${NC}"
echo -e "${CYAN}====== Uso : Usando Bitcoin Core para Transacciones  ======${NC}"
echo -e "${CYAN}===                                                     ===${NC}"

# Paso 14: Generar dirección para Trader
print_separator
echo -e "${CYAN}Paso 14: Generar dirección para la billetera Trader${NC}"
echo -e "${YELLOW}Se espera: Crear una dirección con la etiqueta '${TRADER_LABEL}'${NC}"
TRADER_ADDRESS=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${TRADER_WALLET} getnewaddress "${TRADER_LABEL}")
echo -e "${GREEN}Dirección creada (${TRADER_LABEL}): ${TRADER_ADDRESS}${NC}"
echo -e "${YELLOW}Verificando la etiqueta '${TRADER_LABEL}'...${NC}"
LABELS_TRADER=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${TRADER_WALLET} listlabels)
if echo "${LABELS_TRADER}" | grep -q "${TRADER_LABEL}"; then
    echo -e "${GREEN}Etiqueta '${TRADER_LABEL}' confirmada${NC}"
else
    echo -e "${RED}Error: Etiqueta '${TRADER_LABEL}' no encontrada${NC}"
    exit 1
fi

# Paso 15: Enviar 20 BTC de Miner a Trader
print_separator
echo -e "${CYAN}Paso 15: Enviar 20 BTC de Miner a Trader${NC}"
echo -e "${YELLOW}Se espera: Generar una transacción de 20 BTC desde Miner a Trader${NC}"
TXID=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} sendtoaddress "${TRADER_ADDRESS}" 20)
echo -e "${GREEN}Transacción enviada con txid: ${TXID}${NC}"

# Paso 16: Consultar transacción en el mempool
print_separator
echo -e "${CYAN}Paso 16: Consultar transacción en el mempool${NC}"
echo -e "${YELLOW}Se espera: Mostrar los detalles de la transacción no confirmada${NC}"
MEMPOOL_OUTPUT=$(${EXTRACT_DIR}/bin/bitcoin-cli getmempoolentry "${TXID}")
echo "${MEMPOOL_OUTPUT}"
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Transacción encontrada en el mempool${NC}"
    if echo "${MEMPOOL_OUTPUT}" | grep -q '"unbroadcast": true'; then
        echo -e "${YELLOW}Nota: La transacción no se ha transmitido (normal en regtest)${NC}"
    fi
else
    echo -e "${RED}Error: No se pudo encontrar la transacción en el mempool${NC}"
    exit 1
fi

# Paso 17: Confirmar transacción
print_separator
echo -e "${CYAN}Paso 17: Confirmar la transacción minando un bloque${NC}"
echo -e "${YELLOW}Se espera: Minar un bloque para incluir la transacción${NC}"
${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} generatetoaddress 1 "${MINER_ADDRESS}" > /dev/null
echo -e "${GREEN}Bloque minado para confirmar la transacción${NC}"

# Paso 18: Mostrar detalles de la transacción
print_separator
echo -e "${CYAN}Paso 18: Mostrar detalles de la transacción${NC}"
echo -e "${YELLOW}Se espera: Mostrar txid, cantidades, comisiones, bloque y saldos${NC}"
TX_DETAILS=$(${EXTRACT_DIR}/bin/bitcoin-cli getrawtransaction "${TXID}" true)
BLOCK_HEIGHT=$(${EXTRACT_DIR}/bin/bitcoin-cli getblockcount)
MINER_BALANCE=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} getbalance)
TRADER_BALANCE=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${TRADER_WALLET} getbalance)

# Usar gettransaction para obtener detalles más fiables
TX_DETAILS_ALT=$(${EXTRACT_DIR}/bin/bitcoin-cli -rpcwallet=${MINER_WALLET} gettransaction "${TXID}")
SEND_AMOUNT=$(echo "${TX_DETAILS_ALT}" | jq '.amount | abs')
FEES=$(echo "${TX_DETAILS_ALT}" | jq '.fee | abs // 0.00001410')
# Convertir FEES a formato decimal para bc
FEES=$(printf "%.8f" "${FEES}")
INPUT_AMOUNT=$(echo "${SEND_AMOUNT} + ${FEES}" | bc)
CHANGE_AMOUNT=$(echo "${TX_DETAILS}" | jq '.vout[] | select(.scriptPubKey.addresses[0]=="'${MINER_ADDRESS}'").value // 0')

echo -e "${CYAN}Detalles de la transacción:${NC}"
echo -e "txid: ${TXID}"
echo -e "<Origen, Cantidad> (${MINER_LABEL}): ${MINER_ADDRESS}, ${INPUT_AMOUNT} BTC"
echo -e "<Enviado, Cantidad> (${TRADER_LABEL}): ${TRADER_ADDRESS}, ${SEND_AMOUNT} BTC"
echo -e "<Cambio, Cantidad> (${MINER_LABEL}): ${MINER_ADDRESS}, ${CHANGE_AMOUNT} BTC"
echo -e "Comisiones: ${FEES} BTC"
echo -e "Bloque: ${BLOCK_HEIGHT}"
echo -e "Saldo de Miner (${MINER_LABEL}): ${MINER_BALANCE} BTC"
echo -e "Saldo de Trader (${TRADER_LABEL}): ${TRADER_BALANCE} BTC"

# Nota: Para validar la transaccion se mino un bloque adicional, lo que es normal en regtest.
# Esto asegura que la transacción se confirme y los saldos se actualicen correctamente.
# Y esto genero otra recompensa de bloque, agregando al saldo de Miner otros 50 BTC.
echo -e "${YELLOW}Al minar un bloque adicional para validar la transacción, se añadió una recompensa de bloque de 50 BTC al saldo de Miner correspondiente al bloque 2.${NC}"

# Paso 19: Detener bitcoind
print_separator
echo -e "${CYAN}Paso 19: Detener el nodo de Bitcoin Core${NC}"
echo -e "${YELLOW}Se espera: Cerrar bitcoind correctamente${NC}"
${EXTRACT_DIR}/bin/bitcoin-cli stop
echo -e "${GREEN}Nodo detenido correctamente${NC}"

print_separator
echo -e "${CYAN}=== Ejercicio finalizado ===${NC}"
echo -e "${GREEN}Carpetas ${DOWNLOAD_DIR}, ${EXTRACT_DIR} y ${HOME}/.bitcoin preservadas; puedes eliminarlas si lo deseas.${NC}"