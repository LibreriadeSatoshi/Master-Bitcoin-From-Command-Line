#!/bin/bash

# sources
# https://wolfmcnally.com/115/developer-notes-setting-up-a-bitcoin-node-on-aws/
# https://bitcoincore.org/en/download/

mkdir -p data
cd data

# Descargar bitcoin

wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS
wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS.asc

# Descargar las firmas

git clone https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/*

gpg --verify SHA256SUMS.asc

# # verify
# #sha256sum --ignore-missing --check SHA256SUMS

# Verificacion perzonalizada ;)
if sha256sum --ignore-missing --check SHA256SUMS | grep -q 'OK'; then
  echo "Verificación exitosa de la firma binaria"
fi


# instalar

tar xzf bitcoin-29.0-x86_64-linux-gnu.tar.gz

sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*


# configurar

mkdir -p /home/$(whoami)/.bitcoin/

echo "" > /home/$(whoami)/.bitcoin/bitcoin.conf
echo "regtest=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
echo "fallbackfee=0.0001" >> /home/$(whoami)/.bitcoin/bitcoin.conf
echo "server=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
echo "txindex=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf

# correr
bitcoind -daemon

sleep 3s

# crear billeteras

bitcoin-cli createwallet Miner > /dev/null 2>&1;
bitcoin-cli createwallet Trader > /dev/null 2>&1;

# crear una direccion
direccionRecompensa=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")


# install requirements
# curl -sLo jq https://stedolan.github.io/jq/download/linux64/jq
# chmod +x jq
# sudo mv jq /usr/local/bin/

while ($(jq -n "$(bitcoin-cli -rpcwallet=Miner getbalance) <= 0")) 
  do
    bitcoin-cli generatetoaddress 1 $direccionRecompensa > /dev/null 2>&1;
done

# respuestas parte I

echo "Se necesitaron $(bitcoin-cli getblockcount) bloques para obtener un saldo positivo"
echo "El saldo de la billetera se comporta de esa manera porque las recompensas de minería (coinbase) no se pueden gastar hasta que tengan 100 confirmaciones."
echo "El saldo de la billetera Miner es $( bitcoin-cli -rpcwallet=Miner getbalance | bc ) BTC"

# crear otra direccion
direccionRecibido=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido")


# enviar los btc
txId=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $direccionRecibido 20.0)

# mostrar la mempool
bitcoin-cli getmempoolentry $txId

# minar
bitcoin-cli generatetoaddress 1 $direccionRecompensa > /dev/null 2>&1;

# capturar la transaccion
rawTx=$(bitcoin-cli getrawtransaction $txId 2)

# respuestas parte II
echo "txid: $( echo $rawTx | jq -r '.txid')"
echo "De, Cantidad: $( echo $rawTx | jq -r '.vin[0] .prevout .scriptPubKey .address'), $( echo $rawTx | jq -r '.vin[0] .prevout .value') BTC"
echo "Enviar, Cantidad: $( echo $rawTx | jq -r '.vout[1] .scriptPubKey .address'), $( echo $rawTx | jq -r '.vout[1] .value') BTC"
echo "Cambio, Cantidad: $( echo $rawTx | jq -r '.vout[0] .scriptPubKey .address'), $( echo $rawTx | jq -r '.vout[0] .value') BTC"
echo "Comisiones: $(echo $rawTx | jq -r '.fee' )"
echo "Bloque: $(bitcoin-cli getblock $(echo $rawTx | jq -r '.blockhash' ) 1 | jq -r '.height')"
echo "Saldo de Miner: $( bitcoin-cli -rpcwallet=Miner getbalance)"
echo "Saldo de Trader: $( bitcoin-cli -rpcwallet=Trader getbalance)"

# script para desinstalar bitcoin

# bitcoin-cli stop
# sudo rm -r /usr/local/bin/*bitcoin*
# rm -r /home/$(whoami)/.bitcoin
# cd ..
# rm -rf ./data
