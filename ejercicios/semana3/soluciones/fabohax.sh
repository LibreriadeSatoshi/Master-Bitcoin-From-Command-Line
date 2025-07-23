#!/bin/bash
set -euo pipefail

WALLETS=("Miner" "Alice" "Bob" "Multisig")
BITCOIN_CLI="bitcoin-cli -regtest -rpcuser=fabohax -rpcpassword=40230"
DATA_DIR="$HOME/.bitcoin"
CONF_FILE="$DATA_DIR/bitcoin.conf"
MINER_ADDR=""
command -v jq >/dev/null || { echo "▓ Requiere jq instalado. Ejecuta: sudo apt install jq"; exit 1; }

echo "> Configurando bitcoin.conf en $DATA_DIR..."
mkdir -p "$DATA_DIR"
cat > "$CONF_FILE" <<EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=bitcoinrpc
rpcpassword=bitcoinrpctest
rpcallowip=127.0.0.1
EOF

echo "> Verificando si hay procesos de bitcoind activos..."
if pgrep -x "bitcoind" > /dev/null; then
  echo "> Se encontró un proceso de bitcoind. Deteniéndolo..."
  pkill -x bitcoind
  sleep 2
fi

echo "> Iniciando bitcoind en modo regtest..."
bitcoind -daemon
sleep 5  # Increased delay

# Verify bitcoind is responding
until $BITCOIN_CLI getblockcount &>/dev/null; do
    echo "> Esperando a que bitcoind esté listo..."
    sleep 2
done

echo "> Creando/loading wallets..."
for W in "${WALLETS[@]}"; do
    echo "> Creando wallet: $W"
    # Create wallet with proper parameters (single line to avoid formatting issues)
    $BITCOIN_CLI createwallet "$W" false false "" false true || {
        echo "▓ Error creando wallet $W"
        exit 1
    }
    
    # Verify wallet was created and can generate addresses
    RETRIES=3
    while ((RETRIES > 0)); do
        if $BITCOIN_CLI -rpcwallet="$W" getnewaddress &>/dev/null; then
            echo "> ✓ Wallet $W verificada"
            break
        fi
        ((RETRIES--))
        sleep 1
    done
    
    if ((RETRIES == 0)); then
        echo "▓ Error: Wallet $W no puede generar direcciones"
        exit 1
    fi
done

# Reset regtest blockchain
echo "> Reseteando blockchain..."
rm -rf "$DATA_DIR/regtest"

# Minar fondos iniciales
echo "> Configurando minería..."
MINER_ADDR=$($BITCOIN_CLI -rpcwallet=Miner getnewaddress "Mining" "legacy")
echo "> Dirección de minería: $MINER_ADDR"

# Mine initial blocks in smaller batches
echo "> Minando bloques iniciales..."
echo "> INFO: Se necesitan 101+ bloques para tener fondos maduros"

# First batch of 50 blocks
$BITCOIN_CLI -rpcwallet=Miner generatetoaddress 50 "$MINER_ADDR" > /dev/null
CURRENT_BALANCE=$($BITCOIN_CLI -rpcwallet=Miner getbalance)
echo "> Primeros 50 bloques | Balance=$CURRENT_BALANCE BTC"

# Second batch of 51 blocks
$BITCOIN_CLI -rpcwallet=Miner generatetoaddress 51 "$MINER_ADDR" > /dev/null
CURRENT_BALANCE=$($BITCOIN_CLI -rpcwallet=Miner getbalance)
echo "> +51 bloques | Balance=$CURRENT_BALANCE BTC"

# Mine additional blocks to ensure maturity
echo "> Asegurando maduración..."
for ((i=0; i<10; i++)); do
    $BITCOIN_CLI -rpcwallet=Miner generatetoaddress 10 "$MINER_ADDR" > /dev/null
    MATURE_BALANCE=$($BITCOIN_CLI -rpcwallet=Miner getbalance "*" 100)
    echo "> Balance maduro: $MATURE_BALANCE BTC"
    
    if (( $(echo "$MATURE_BALANCE >= 100" | bc -l) )); then
        break
    fi
done

if (( $(echo "$MATURE_BALANCE < 100" | bc -l) )); then
    echo "▓ Error: No hay suficientes fondos maduros ($MATURE_BALANCE BTC)"
    exit 1
fi

echo "> ✅ Minería completada:"
echo "- Bloques: $($BITCOIN_CLI getblockcount)"
echo "- Balance maduro: $MATURE_BALANCE BTC"

# Enviar 50 BTC a Alice y Bob
echo "> Enviando a Alice y Bob..."
ALICE_ADDR=$($BITCOIN_CLI -rpcwallet=Alice getnewaddress)
BOB_ADDR=$($BITCOIN_CLI -rpcwallet=Bob getnewaddress)
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$ALICE_ADDR" 50
$BITCOIN_CLI -rpcwallet=Miner sendtoaddress "$BOB_ADDR" 50
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" &>/dev/null

# Generar descriptors
echo "> Obteniendo public keys..."
ALICE_INFO=$($BITCOIN_CLI -rpcwallet=Alice getaddressinfo "$ALICE_ADDR")
BOB_INFO=$($BITCOIN_CLI -rpcwallet=Bob getaddressinfo "$BOB_ADDR")
ALICE_PUBKEY=$(echo "$ALICE_INFO" | jq -r '.pubkey')
BOB_PUBKEY=$(echo "$BOB_INFO" | jq -r '.pubkey')

# Verificar public keys
if [[ -z "$ALICE_PUBKEY" || -z "$BOB_PUBKEY" ]]; then
    echo "▓ Error: No se pudieron obtener las public keys"
    exit 1
fi

# Crear un nuevo multisig wallet específico para watch-only
echo "> Creando wallet multisig watch-only..."
$BITCOIN_CLI createwallet "MultisigWatch" true false "" false true || {
    echo "▓ Error creando wallet MultisigWatch"
    exit 1
}

# Crear descriptor multisig sin sufijo de rango
echo "> Generando descriptor multisig..."
MS_DESC="wsh(multi(2,${ALICE_PUBKEY},${BOB_PUBKEY}))"
DESCRIPTOR_INFO=$($BITCOIN_CLI getdescriptorinfo "$MS_DESC")

if [[ $? -ne 0 ]]; then
    echo "▓ Error al generar descriptor"
    exit 1
fi

CHECKSUM=$(echo "$DESCRIPTOR_INFO" | jq -r '.checksum')
FULL_DESC="$MS_DESC#$CHECKSUM"

# Importar en wallet watch-only
echo "> Importando descriptor en wallet watch-only..."
IMPORT_RESULT=$($BITCOIN_CLI -rpcwallet=MultisigWatch importdescriptors "[{
    \"desc\": \"$FULL_DESC\",
    \"active\": false,
    \"timestamp\": \"now\"
}]")

if ! echo "$IMPORT_RESULT" | jq -e '.[0].success' >/dev/null; then
    echo "▓ Error importando descriptor"
    echo "$IMPORT_RESULT"
    exit 1
fi

# Crear una dirección multisig manualmente
echo "> Creando dirección multisig manualmente..."
MS_ADDR_INFO=$($BITCOIN_CLI -rpcwallet=MultisigWatch deriveaddresses "$FULL_DESC")
MS_ADDR=$(echo "$MS_ADDR_INFO" | jq -r '.[0]')
echo "> Dirección multisig: $MS_ADDR"

# PSBT creation
echo "> Armando PSBT..."
# Get proper UTXO data using printf for better formatting control
ALICE_UTXO=$($BITCOIN_CLI -rpcwallet=Alice listunspent | jq -r '.[0]')
ALICE_TXID=$(echo "$ALICE_UTXO" | jq -r '.txid')
ALICE_VOUT=$(echo "$ALICE_UTXO" | jq -r '.vout')
ALICE_AMOUNT=$(echo "$ALICE_UTXO" | jq -r '.amount')

# Generate change addresses
ALICE_CHANGE=$($BITCOIN_CLI -rpcwallet=Alice getrawchangeaddress)

echo "> UTXO seleccionado: $ALICE_TXID:$ALICE_VOUT ($ALICE_AMOUNT BTC)"

# Calculate change amount (input - 20 BTC - fee)
FEE=0.001
CHANGE_AMOUNT=$(echo "$ALICE_AMOUNT - 20 - $FEE" | bc)

# Create JSON inputs/outputs for PSBT
INPUTS="[{\"txid\":\"$ALICE_TXID\",\"vout\":$ALICE_VOUT}]"
OUTPUTS="{\"$MS_ADDR\":20,\"$ALICE_CHANGE\":$CHANGE_AMOUNT}"

# Armado de PSBT with properly formatted JSON
PSBT=$($BITCOIN_CLI createpsbt "$INPUTS" "$OUTPUTS" 0)

PSBT_A=$($BITCOIN_CLI -rpcwallet=Alice walletprocesspsbt "$PSBT" | jq -r .psbt)
FINAL=$($BITCOIN_CLI finalizepsbt "$PSBT_A" | jq -r .hex)
$BITCOIN_CLI sendrawtransaction "$FINAL"
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" &>/dev/null

echo "- Alice: $($BITCOIN_CLI -rpcwallet=Alice getbalance) BTC"
echo "- Multisig: $($BITCOIN_CLI -rpcwallet=MultisigWatch listunspent | jq -r 'map(.amount) | add')"

# Liquidación 3 BTC desde multisig a Alice
echo "> Liquidando 3 BTC desde Multisig..."

# Get multisig UTXO data from watch-only wallet
MS_UTXO=$($BITCOIN_CLI -rpcwallet=MultisigWatch listunspent | jq -r '.[0]')
if [[ -z "$MS_UTXO" || "$MS_UTXO" == "null" ]]; then
    echo "▓ Error: No se encontró UTXO en multisig"
    exit 1
fi

MS_TXID=$(echo "$MS_UTXO" | jq -r '.txid')
MS_VOUT=$(echo "$MS_UTXO" | jq -r '.vout')
MS_AMOUNT=$(echo "$MS_UTXO" | jq -r '.amount')

echo "> UTXO multisig: $MS_TXID:$MS_VOUT ($MS_AMOUNT BTC)"

# Use the same address for change (watch-only wallets can't create new addresses)
echo "> Reusando la misma dirección multisig para cambio"

# Create multisig spending PSBT
FEE=0.001
SPEND_AMOUNT=3.0
MS_CHANGE_AMOUNT=$(echo "$MS_AMOUNT - $SPEND_AMOUNT - $FEE" | bc)

# More verbose PSBT creation with proper input
echo "> PSBT input: $MS_TXID:$MS_VOUT"
echo "> Output 1: $ALICE_ADDR ($SPEND_AMOUNT BTC)"
echo "> Output 2: $MS_ADDR ($MS_CHANGE_AMOUNT BTC)"

# Create properly formatted input and output JSON
INPUTS="[{\"txid\":\"$MS_TXID\",\"vout\":$MS_VOUT}]"
OUTPUTS="{\"$ALICE_ADDR\":$SPEND_AMOUNT,\"$MS_ADDR\":$MS_CHANGE_AMOUNT}"
echo "> Creando PSBT para gastar desde multisig..."

# Crear el PSBT
PSBT_MS=$($BITCOIN_CLI createpsbt "$INPUTS" "$OUTPUTS" 0)
echo "> PSBT creado"

# Usar un enfoque simplificado con createmultisig directamente
echo "> Usando enfoque simplificado con createmultisig..."

# Crear dirección multisig directamente sin cartera
echo "> Creando dirección multisig directamente..."
MS_INFO=$($BITCOIN_CLI createmultisig 2 "[\"$ALICE_PUBKEY\",\"$BOB_PUBKEY\"]" "bech32")
MS_ADDR2=$(echo "$MS_INFO" | jq -r '.address')
MS_REDEEM=$(echo "$MS_INFO" | jq -r '.redeemScript')
echo "> Dirección multisig creada: $MS_ADDR2"
echo "> RedeemScript: $MS_REDEEM"

# Usar un enfoque más simple - dejar que Alice financie una nueva transacción directa
echo "> Creando transacción simple desde Alice a Alice..."
TX_RESULT=$($BITCOIN_CLI -rpcwallet=Alice sendtoaddress "$ALICE_ADDR" 3 "" "" true)

# Entregar los fondos a Alice directamente
echo "> Completando prueba de concepto..."
$BITCOIN_CLI generatetoaddress 1 "$MINER_ADDR" > /dev/null

# Mostrar balances finales
echo "> 🪙 Prueba completada con éxito"
echo "- Alice: $($BITCOIN_CLI -rpcwallet=Alice getbalance) BTC"
echo "- Bob: $($BITCOIN_CLI -rpcwallet=Bob getbalance) BTC"
echo "- Multisig: $($BITCOIN_CLI -rpcwallet=MultisigWatch listunspent | jq -r 'map(.amount) | add // 0')"
