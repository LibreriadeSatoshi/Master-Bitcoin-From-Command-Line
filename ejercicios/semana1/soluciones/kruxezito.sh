#!/bin/bash

# CONFIGURACION

# Aqui utilice linux como archivo para descargar por defecto.
FILE=bitcoin-30.2-x86_64-linux-gnu.tar.gz

# Asegurandome de Descargar el archivo correcto.

if [[ "$OSTYPE" == "darwin"* ]]; then

	# Confirmando si esta brew instalado, Si no es asi lo descargo...
	[ ! command -v brew &> /dev/null ] && /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
	brew install gnupg jq 2> /dev/null
	
	# File para Apple Chips M#
	FILE="bitcoin-30.2-x86_64-apple-darwin.tar.gz"

else
	sudo apt-get update && sudo apt-get install -y gnupg jq wget curl 2> /dev/null
fi

CURRENT_DIR=$(pwd)

echo "======================================"
echo "Intentando obtener Bitcoin-core..."
echo "======================================"

# Descargando los binarios principales

if [ ! -e "$CURRENT_DIR/$FILE" ]; then
	echo "Descargando Bitcoin-core..."
	wget -q https://bitcoincore.org/bin/bitcoin-core-30.2/$FILE
else
	echo -e "Bitcoin-core ya existe en esta carpeta. \n"
fi

[ ! -f "$CURRENT_DIR/SHA256SUMS" ] && wget -q https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS
[ ! -f "$CURRENT_DIR/SHA256SUMS.asc" ] && wget -q https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS.asc

echo "---------------------------------------"
echo "Verificando Checksum..."
echo "---------------------------------------"

# Checksum
sha256sum --ignore-missing --check SHA256SUMS

echo -e "\n"
echo "---------------------------------------"
echo "Descargando firmas..."
echo "---------------------------------------"

if [ ! -d "gpg-keys" ]; then
	mkdir -p gpg-keys
	echo "Descargando llaves desde github"
	curl -s https://api.github.com/repos/bitcoin-core/guix.sigs/contents/builder-keys | jq -r '.[].download_url' | wget -q -i - -P gpg-keys/
else
	echo "Las llaves ya existen en gps-keys"
fi

echo "Importando firmas..."
gpg --import gpg-keys/*.gpg &> /dev/null

echo "Verificando Firmas..."
if gpg --verify SHA256SUMS.asc &> /dev/null; then
	echo "🎉 Verificación exitosa de la firma binaria"
else
	echo -e "Error en la firma"
	exit 1
fi

tar xzf $FILE

# Instalando los binarios en $Home/bin.
if [[ "$OSTYPE" == "darwin"* ]]; then
	sudo install -m 0755 bitcoin-30.2/bin/* $HOME/bin/ &> /dev/null
else
	sudo install -m 0755 -o root -g root -t $HOME/bin bitcoin-30.2/bin/* &> /dev/null
fi
# Asegurarme que la carpeta .bitcoin exista.
[ ! -d "$HOME/.bitcoin" ] && mkdir $HOME/.bitcoin &> /dev/null
cd $HOME/.bitcoin

# INICIO

# Creando bitcoin.conf si no existe.
if [ ! -e "bitcoin.conf" ]; then
	touch bitcoin.conf
fi

# Inyectar los parametros por defecto bitcoin.conf.
> bitcoin.conf
echo "regtest=1" >> bitcoin.conf
echo "fallbackfee=0.0001" >> bitcoin.conf
echo "server=1" >> bitcoin.conf
echo "txindex=1" >> bitcoin.conf

# Confirmando que Bitcoind se haya instalado.
if command -v bitcoind &> /dev/null; then
	echo "Bitcoin Core se instalo correctamente."
	echo "......................................"
	echo "Inicializando Bitcoin Core..."

	# Esta el proceso de bitcoind activo?, si no levantarlo en modo daemon.
	if ! pgrep -f bitcoind &> /dev/null; then
		if [[ "$OSTYPE" == "darwin"* ]]; then
			$HOME/bin/bitcoind -conf="$HOME/.bitcoin/bitcoin.conf" --daemon
		else
			bitcoind -conf="$HOME/.bitcoin/bitcoin.conf" --daemon
		fi
	else
		echo "Bitcoin core ya esta corriendo"
	fi
else
	echo "No se encuenta el bitcoind en el PATH. Revisa la instalacion."
fi

# Durmiendo el processo por 5 segundo para asegurarme que bitcoind se levante correctamente.
sleep 5

btr_cli="bitcoin-cli -conf=$HOME/.bitcoin/bitcoin.conf"

# Creando/Cargando (Miner/Trader) Wallets.
$btr_cli createwallet "Miner" > /dev/null 2>&1 || $btr_cli loadwallet "Miner" > /dev/null 2>&1
$btr_cli createwallet "Trader" > /dev/null 2>&1 || $btr_cli loadwallet "Trader" > /dev/null 2>&1

# Generando Direccion del minero para la recompensa por mineria.
address_minero=$($btr_cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")

# Extrayendo 101 blocks para poder tener saldo positivo.
$btr_cli -rpcwallet=Miner generatetoaddress 101 $address_minero &> /dev/null

: '
Para que el saldo de la mineria sea positivo y valido para gastar, Es necesario que el minero espere 100 blocks extras. para asi
validar que no se haya creado un fork o una reorganizacion de la cadena que les pueda invalidar sus transacciones y generar
un caos total ya que desaparecerian esos UTXO.
'

saldo_minero=$($btr_cli -rpcwallet=Miner getbalance)
echo -e "\n"

# Imprimiendo saldo de minero.
echo "======================================"
echo "Saldo de Minero: $saldo_minero"
echo -e "====================================== \n"

# USO

# Generar direccion receptora del Trader.
address_recibido=$($btr_cli -rpcwallet=Trader getnewaddress Recibido)

# Minero pagando 20 BTC a el Trader.
txid=$($btr_cli -rpcwallet=Miner sendtoaddress $address_recibido 20)

# Transaccion no confirmada de la Mempool.
echo "Mempool Transaccion: $($btr_cli -rpcwallet=Trader getmempoolentry $txid | jq '.')"

# Obteniendo Fee desde la Mempool.
fee=$(echo "$($btr_cli -rpcwallet=Trader getmempoolentry $txid | jq '.fees.base')")

# Confirmando transaccion generando 1 block.
$btr_cli -rpcwallet=Miner generatetoaddress 1 $address_minero &> /dev/null

# Raw Transaccion para poder obtener los datos requeridos.
raw_tx=$($btr_cli -rpcwallet=Miner getrawtransaction $txid 1)

# Obteniendo Outpoints. 
outpoints=$(jq '.vin | map({txid: .txid, vout: .vout})' <<< $raw_tx)

# Filtrando los datos requeridos del Change-output.
change_vout=$(jq -r --arg DEST $address_recibido '.vout[] | select(.scriptPubKey.address != $DEST)' <<< $raw_tx)

# Change.
change_value=$(echo $change_vout | jq -r '.value')
# Dirrecion a Enviar el Change.
change_address=$(echo $change_vout | jq -r '.scriptPubKey.address')

# Filtrando a donde se pago.
sent_vout=$(jq -r --arg DEST $address_recibido '.vout[] | select(.scriptPubKey.address == $DEST)' <<< $raw_tx)
# Monto pagado.
sent_value=$(echo $sent_vout | jq -r '.value')

# Iterando sobre los Outpoints para poder sacar los montos iniciales.
values=$(echo $outpoints | jq -c '.[]' | while read -r outpoint; do
	prev_txid=$(echo $outpoint | jq -r '.txid')
        prev_vout=$(echo $outpoint | jq -r '.vout')
	$btr_cli getrawtransaction $prev_txid 1 | jq -r ".vout[$prev_vout].value"
done)

# Sumando montos.
input_value=$(echo "$values" | jq -s 'add')

# Consiguiendo la altura del block donde se confirmo la transaccion.
block_hash=$(jq -r '.blockhash' <<< $raw_tx)
block_height=$($btr_cli getblock $block_hash | jq '.height')

# Actualizacion de los Saldos.
saldo_miner=$($btr_cli -rpcwallet=Miner getbalance)
saldo_trader=$($btr_cli -rpcwallet=Trader getbalance)

# Terminal Output.
echo -e "\n"
echo "Txid: $txid"
echo "<De, Cantidad>: $address_minero, $input_value"
echo "<Enviar, Cantidad>: $address_recibido, $sent_value"
echo "<Cambio, Cantidad>: $change_address, $change_value"
echo "Comisiones: $fee"
echo "Bloque: $block_height"
echo "Saldo de Miner: $saldo_miner"
echo "Saldo de Trader: $saldo_trader"
