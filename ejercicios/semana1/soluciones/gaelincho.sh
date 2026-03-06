#!/bin/bash

# mkdir /tmp/bitcoin-download
# cd /tmp/bitcoin-download
mkdir $HOME/temp_bitcoin
cd $HOME/temp_bitcoin

### CONFIG
wget https://bitcoincore.org/bin/bitcoin-core-30.2/bitcoin-30.2-x86_64-linux-gnu.tar.gz -q
tar -xzf bitcoin-30.2-x86_64-linux-gnu.tar.gz
wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS -q
wget https://bitcoincore.org/bin/bitcoin-core-30.2/SHA256SUMS.asc -q

sha256sum --ignore-missing --check SHA256SUMS | grep -v OK 
if [ $? -eq 0 ]; then
    echo "Verificación exitosa de la firma binaria"
else
    exit 1
fi

rm -r $HOME/temp_bitcoin

### INICIO

mkdir -p "$HOME/.bitcoin"
touch "$HOME/.bitcoin/bitcoin.conf"
echo -e "regtest=1\nfallbackfee=0.0001\nserver=1\ntxindex=1" >> "$HOME/.bitcoin/bitcoin.conf"

alias bitcoind="$HOME/bitcoin-30.2/bin/bitcoind"
alias bitcoin-cli="$HOME/bitcoin-30.2/bin/bitcoin-cli"

bitcoind -daemon

sleep 5

bitcoin-cli -regtest createwallet "Miner" > /dev/null
bitcoin-cli -regtest createwallet "Trader" > /dev/null

maddr=$(bitcoin-cli -regtest -rpcwallet="Miner" getnewaddress "Recompensa de Mineria")

bitcoin-cli -regtest generatetoaddress 101 $maddr > /dev/null # Esto es porque bitcoin no deja gastar UTXOs de la coinbase de hace menos que 100 bloques.

bitcoin-cli -regtest -rpcwallet="Miner" listunspent | jq -r '.[].amount' | awk '{sum += $1} END {print sum}'


### USO

raddr=$(bitcoin-cli -regtest -rpcwallet="Trader" getnewaddress "Recibido")

txid=$(bitcoin-cli -regtest -rpcwallet="Miner" -named sendtoaddress address="$raddr" amount=20 fee_rate=15)

bitcoin-cli -regtest getmempoolentry $txid

bitcoin-cli -regtest -rpcwallet="Miner" generatetoaddress 1 $maddr > /dev/null

tx=$(bitcoin-cli -regtest getrawtransaction $txid 2)

# tx=$(bitcoin-cli -regtest decoderawtransaction $rtx)


ptxid=$(echo $tx | jq -r '.txid')
pfrom=$(echo $tx | jq -r '.vin[0].prevout.scriptPubKey.address')
pin=$(echo $tx | jq -r '.vin[0].prevout.value')
pvout1=$(echo $tx | jq -r '.vout[0].value')
pvout2=$(echo $tx | jq -r '.vout[1].value')
coms=$(echo "$pin - $pvout1 - $pvout2" | bc -l)


echo "txid: $ptxid
De: $pfrom, Cantidad: $pin
Enviar: $(echo $tx | jq -r '.vout[1].scriptPubKey.address'), Cantidad: $pvout2
Cambio: $(echo $tx | jq -r '.vout[0].scriptPubKey.address'), Cantidad: $pvout1
Comisiones: $pin - $pvout1 - $pvout2 = $coms
Bloque: $(bitcoin-cli -regtest getblockcount)
Saldo de Miner: $(bitcoin-cli -regtest -rpcwallet="Miner" getbalance)
Saldo de Trader: $(bitcoin-cli -regtest -rpcwallet="Trader" getbalance)"
