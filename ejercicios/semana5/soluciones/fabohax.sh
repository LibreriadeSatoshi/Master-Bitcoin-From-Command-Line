#!/bin/bash
set -euo pipefail

DATA_DIR="$HOME/.bitcoin"
CONF_FILE="$DATA_DIR/bitcoin.conf"

# Configuración inicial de Bitcoin Core
echo "> Configurando entorno en $DATA_DIR..."
mkdir -p "$DATA_DIR"
cat > "$CONF_FILE" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=fabohax
rpcpassword=40230
rpcallowip=127.0.0.1
EOF

# Detener cualquier instancia previa de bitcoind y limpiar datos
echo "> Reiniciando bitcoind si está activo..."
if pgrep -x "bitcoind" > /dev/null; then
  bitcoin-cli -regtest stop 2>/dev/null || pkill -x bitcoind
  sleep 3
fi

# Limpiar completamente el directorio regtest
echo "> Limpiando datos regtest..."
rm -rf "$DATA_DIR/regtest"

# Iniciar bitcoind en modo regtest
echo "> Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 3

# Definir BITCOIN_CLI después de que bitcoind esté corriendo
BITCOIN_CLI="bitcoin-cli -regtest -rpcuser=fabohax -rpcpassword=40230"

# Esperar a que bitcoind esté completamente listo
echo "> Esperando a que bitcoind esté listo..."
while ! $BITCOIN_CLI getblockchaininfo >/dev/null 2>&1; do
  sleep 1
done

# === Verificar herramientas necesarias ===
command -v bc >/dev/null 2>&1 || { echo >&2 "▓ Error: 'bc' no está instalado. Ejecuta: sudo apt install bc"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "▓ Error: 'jq' no está instalado. Ejecuta: sudo apt install jq"; exit 1; }

# === Crear wallets para el ejercicio de timelock relativo ===
for WALLET in Miner Alice; do
    echo "> Creando nueva wallet '$WALLET'..."
    $BITCOIN_CLI -named createwallet wallet_name=$WALLET descriptors=true load_on_startup=true
done

# Obtener dirección de minería
MINER_ADDR=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress "Miner" legacy)

# Minar bloques en lotes grandes
echo "> Minando 150 bloques para asegurar maduración..."
$BITCOIN_CLI -rpcwallet=Miner generatetoaddress 150 "$MINER_ADDR" >/dev/null

# Verificar balance
MATURE_BALANCE=$($BITCOIN_CLI -rpcwallet=Miner getbalance "*" 1)
echo "> Saldo maduro de Miner: $MATURE_BALANCE BTC"

# === Fondear Alice ===
echo "> Enviando 50 BTC a Alice..."
ADDR_ALICE=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress)
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$ADDR_ALICE" 50 >/dev/null
$BITCOIN_CLI -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" >/dev/null

echo "> Confirmando transacción y verificando saldo de Alice..."
echo "Alice: $($BITCOIN_CLI -rpcwallet=Alice getbalance) BTC"

# === Crear transacción con timelock relativo ===
echo "> Creando transacción con timelock relativo de 10 bloques..."

# Obtener UTXO de Alice
UTXO_ALICE=$($BITCOIN_CLI -rpcwallet=Alice listunspent | jq -r '.[0]')
TXID_ALICE=$(echo "$UTXO_ALICE" | jq -r .txid)
VOUT_ALICE=$(echo "$UTXO_ALICE" | jq -r .vout)
AMOUNT_ALICE=$(echo "$UTXO_ALICE" | jq -r .amount)

# Calcular el cambio que regresa a Alice
PAYMENT_AMOUNT=10
FEE_AMOUNT=0.001
CHANGE_ALICE=$(echo "$AMOUNT_ALICE - $PAYMENT_AMOUNT - $FEE_AMOUNT" | bc)

# Crear dirección de cambio para Alice
ALICE_CHANGE_ADDR=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress)

# Crear transacción raw con sequence relativo (10 bloques)
echo "> Creando transacción raw con sequence relativo de 10 bloques..."
RAW_TX=$($BITCOIN_CLI createrawtransaction "[{\"txid\":\"$TXID_ALICE\",\"vout\":$VOUT_ALICE,\"sequence\":10}]" "{\"$MINER_ADDR\":$PAYMENT_AMOUNT,\"$ALICE_CHANGE_ADDR\":$CHANGE_ALICE}")

# Firmar la transacción con la wallet de Alice
echo "> Firmando transacción..."
SIGNED_TX=$($BITCOIN_CLI -rpcwallet=Alice signrawtransactionwithwallet "$RAW_TX")
COMPLETE_TX=$(echo "$SIGNED_TX" | jq -r .hex)

# Obtener bloque actual para referencia
CURRENT_BLOCK=$($BITCOIN_CLI getblockcount)
echo "> Bloque actual: $CURRENT_BLOCK"

# Intentar transmitir inmediatamente (debería fallar)
echo "> Intentando difundir transacción con timelock relativo inmediatamente..."

set +e
BROADCAST_RESULT=$($BITCOIN_CLI sendrawtransaction "$COMPLETE_TX" 2>&1)
BROADCAST_SUCCESS=$?
set -e

if [ $BROADCAST_SUCCESS -ne 0 ]; then
    echo "▓ Como se esperaba, la transacción fue rechazada:"
    echo "   $BROADCAST_RESULT"
    echo "   Comentario: La transacción tiene un timelock relativo de 10 bloques."
    echo "   Esto significa que debe pasar al menos 10 bloques desde que se confirmó"
    echo "   la transacción que contiene el UTXO de entrada antes de poder gastar."
else
    echo "▓ Inesperado: La transacción fue aceptada inmediatamente"
fi

# === Gastar desde el timelock relativo ===
echo "> Generando 10 bloques adicionales para cumplir el timelock relativo..."

# Minar exactamente 10 bloques adicionales
for i in {1..10}; do
    $BITCOIN_CLI -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" > /dev/null
    NEW_BLOCK=$($BITCOIN_CLI getblockcount)
    echo "  > Bloque minado: $NEW_BLOCK (progreso: $i/10)"
done

# Ahora la transacción debería ser aceptada
echo "> Difundiendo la segunda transacción después de 10 bloques..."
PAYMENT_TXID=$($BITCOIN_CLI sendrawtransaction "$COMPLETE_TX")
echo "> Transacción de pago transmitida: $PAYMENT_TXID"

# Confirmar la transacción generando un bloque más
echo "> Confirmando transacción generando un bloque adicional..."
$BITCOIN_CLI -rpcwallet=Miner generatetoaddress 1 "$MINER_ADDR" > /dev/null

# === Mostrar resultados finales ===
echo "> ▓ Saldo final de Alice:"
echo "Alice: $($BITCOIN_CLI -rpcwallet=Alice getbalance) BTC"

echo "> ▓ Resumen del ejercicio:"
echo "   - Bloque inicial: $CURRENT_BLOCK"
echo "   - Bloque final: $($BITCOIN_CLI getblockcount)"
echo "   - Bloques transcurridos: $(($($BITCOIN_CLI getblockcount) - $CURRENT_BLOCK))"
echo "   - Timelock relativo: 10 bloques"

echo "▓ Ejercicio de timelock relativo completado con éxito."
echo "   - Se creó una transacción con timelock relativo de 10 bloques"
echo "   - Se demostró que la transacción es rechazada antes del timelock"
echo "   - Se minaron 10 bloques adicionales para satisfacer el timelock"
echo "   - Se difundió exitosamente la transacción después del período de espera"
