#!/bin/bash

echo "Iniciando"

#Configuración
BITCOIN_VERSION="29.0"
TARFILE="bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
BASE_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"
WORKDIR="/opt/bitcoin"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

[ -f "$TARFILE" ] || wget -q --show-progress "${BASE_URL}/${TARFILE}"
[ -f "SHA256SUMS" ] || wget -q --show-progress "${BASE_URL}/SHA256SUMS"
[ -f "SHA256SUMS.asc" ] || wget -q --show-progress "${BASE_URL}/SHA256SUMS.asc"

if sha256sum --ignore-missing --check SHA256SUMS | grep -q "${TARFILE}: OK"; then
        echo
else
    echo "Checksum verification failed. Exiting."
    exit 1
fi

git clone -q https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/*
if ! gpg --verify SHA256SUMS.asc 2>&1 | grep -q "Good signature from"; then
    exit 1
fi
echo "Verificación exitosa de la firma binaria"


tar -xzf "$TARFILE"
ln -sf "$WORKDIR/bitcoin-${BITCOIN_VERSION}/bin/"* /usr/local/bin/


cd ~
mkdir -p ~/.bitcoin
CONF="~/.bitcoin/bitcoin.conf"

if [ ! -f "$CONF" ]; then
  cat <<EOF > "$CONF"
regtest=1
fallbackfee=0.0001
server=1
txindex=1
rpcuser=satoshi
rpcpassword=satoshi
EOF
  echo "Creando archivo bitcoin.conf en $CONF"
else
  echo "Ya existe un archivo bitcoin.conf"
fi

bitcoind -daemon
sleep 3
bitcoin-cli createwallet "Miner" > /dev/null
bitcoin-cli createwallet "Trader" > /dev/null
miner_address=$(bitcoin-cli -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")


blocks=0
balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
#echo $balance

while [ "$balance" == "0.00000000" ]; do
  #echo "Generando bloques"
  bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address > /dev/null
  balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
  blocks=$((blocks + 1))

done
echo "El saldo de Miner es: $balance"
echo "Se necesitaron minar $blocks bloques"
echo "Cada recompensa de minado, requiere 100 confirmaciones para que el saldo sea efectivo"

trader_address=$(bitcoin-cli -rpcwallet="Trader" getnewaddress "Recibido")
txid=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $trader_address 20)
#echo $txid
#Minar un bloque adicional
blockhash=$(bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $miner_address)

#Json tx
jsontx=$(bitcoin-cli getrawtransaction "$txid" true)


# Datos de la transaccion anterior
vin_txid=$(echo "$jsontx" | jq -r '.vin[0].txid')
vin_vout=$(echo "$jsontx" | jq -r '.vin[0].vout')
input_details=$(bitcoin-cli getrawtransaction "$vin_txid" true)
input_value=$(echo "$input_details" | jq ".vout[$vin_vout].value")
input_address=$(echo "$input_details" | jq -r ".vout[$vin_vout].scriptPubKey.address")

# Datos de salida
vout0_value=$(echo "$jsontx" | jq -r '.vout[0].value')
vout0_address=$(echo "$jsontx" | jq -r '.vout[0].scriptPubKey.address')

vout1_value=$(echo "$jsontx" | jq -r '.vout[1].value')
vout1_address=$(echo "$jsontx" | jq -r '.vout[1].scriptPubKey.address')

# Determinar cuál es Trader y cuál es el cambio
if [ "$vout0_address" == "$trader_address" ]; then
  sent_amount=$vout0_value
  change_amount=$vout1_value
  change_address=$vout1_address
else
  sent_amount=$vout1_value
  change_amount=$vout0_value
  change_address=$vout0_address
fi

# Calcular comisión
total_out=$(echo "$sent_amount + $change_amount" | bc)
fee=$(echo "$input_value - $total_out" | bc)

# Bloque
blockhash=$(echo "$jsontx" | jq -r .blockhash)
blockheight=$(bitcoin-cli getblock "$blockhash" | jq -r .height)

# Saldos
balance_miner=$(bitcoin-cli -rpcwallet=Miner getbalance)
balance_trader=$(bitcoin-cli -rpcwallet=Trader getbalance)

# Mostrar resultado
echo
echo "🔎 Detalles de la transacción:"
echo "txid: $txid"
echo "<De, Cantidad>: $miner_address, $input_value BTC"
echo "<Enviar, Cantidad>: $trader_address, $sent_amount BTC"
echo "<Cambio, Cantidad>: $change_address, $change_amount BTC"
echo "Comisiones: $fee BTC"
echo "Bloque: $blockheight"
echo "Saldo de Miner: $balance_miner BTC"
echo "Saldo de Trader: $balance_trader BTC"
