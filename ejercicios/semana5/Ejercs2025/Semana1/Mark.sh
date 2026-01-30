#!/bin/bash

#--------------------------------------------------------------

# Script de la configuración de Bitcoin Core en RegTest
# Por : Mark

#-------------------------------------------------------------

function Descargas 
{
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS
   wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS.asc
}

function verificacion 
{
   sha256sum --ignore-missing --check SHA256SUMS
   gpg --verify SHA256SUMS.asc
}
echo "Suma de verificación correcta."

 git clone https://github.com/bitcoin-core/guix.sigs
 gpg --import guix.sigs/builder-keys/*

 gpg --verify SHA256SUMS.asc SHA256SUMS 

Verificación exitosa de la firma binaria


function instalacion 
{
   tar -zxvf bitcoin-29.0-x86_64-linux-gnu.tar.gz 
   sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*
}
function configuracion 
{
   mkdir /home/ubuntu/.bitcoin/
   cd /home/ubuntu/.bitcoin/
   echo -e  "regtest=1 \nfallbackfee=0.0001 \nserver=1 \ntxindex=1" > bitcoin.conf
}
bitcoind -daemon
ll ~/.bitcoin/

function createwallet
bitcoin-cli createwallet "Miner"
{
  "name": "Miner"
}
bitcoin-cli createwallet "Trader"
{
  "name": "Trader"
}
function createaddress

(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
(( $(echo "$(bitcoin-cli -rpcwallet=Miner getbalance) <= 0" | bc -l) ))
(bitcoin-cli getblockcount)
(bitcoin-cli -rpcwallet=Miner getbalance)
bitcoin-cli listwallets
bitcoin-cli -rpcwallet=$MINER_WALLET generatetoaddress 101 "bcrt1q887298qpj5fgt7tfmcnqnmlp0g8nam4048whsn"

bitcoin-cli "-rpcwallet=Miner" getbalance

bitcoin-cli -rpcwallet=Trader getnewaddress "Recibido"
bcrt1q6wqfz409wlp8vsr5f2lqpjy0dqmjwsqlgc3nc9

bitcoin-cli getblockchaininfo | jq -r '.blocks'

bitcoin-cli -rpcwallet=Miner sendtoaddress "bcrt1q6wqfz409wlp8vsr5f2lqpjy0dqmjwsqlgc3nc9" 20
3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9
bitcoin-cli getmempoolentry "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9"
{
  "vsize": 141,
  "weight": 561,
  "time": 1751919053,
  "height": 102,
  "descendantcount": 1,
  "descendantsize": 141,
  "ancestorcount": 1,
  "ancestorsize": 141,
  "wtxid": "2662599c39930c5433248b0131eb2c6f962bd4829426fe47907fe96992bb4732",
  "fees": {
    "base": 0.00001410,
    "modified": 0.00001410,
    "ancestor": 0.00001410,
    "descendant": 0.00001410
  },
  "depends": [
  ],
  "spentby": [
  ],
  "bip125-replaceable": true,
  "unbroadcast": true
}

bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "bcrt1q887298qpj5fgt7tfmcnqnmlp0g8nam4048whsn"
[
  "1f164136ae3368cbdd110b78acc8d8afb734868ce1b0b4b7c8d9494f8f3d72eb"
]

bitcoin-cli getrawtransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" true
{
  "txid": "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9",
  "hash": "2662599c39930c5433248b0131eb2c6f962bd4829426fe47907fe96992bb4732",
  "version": 2,
  "size": 222,
  "vsize": 141,
  "weight": 561,
  "locktime": 102,
  "vin": [
    {
      "txid": "6a1df54aaa94ac057f4beacb690557023e2fd0320ca65e576cef5360fed84411",
      "vout": 0,
      "scriptSig": {
        "asm": "",
        "hex": ""
      },
      "txinwitness": [
        "304402206e01039901a5452e15b47b8a19aaf88e451629832e8489c7cfb0fe2d5ad434d4022073cb43c25f94f86bce413f1644c3eecfbf8efb575ac8018e1536833446553d6a01",
        "02b4ff64dd5c438a603d09f4fe760ee6cbe913a42bfb1bf0656bfea2e321ae0d47"
      ],
      "sequence": 4294967293
    }
  ],
  "vout": [
    {
      "value": 20.00000000,
      "n": 0,
      "scriptPubKey": {
        "asm": "0 d3809155e577c27640744abe00c88f683727401f",
        "desc": "addr(bcrt1q6wqfz409wlp8vsr5f2lqpjy0dqmjwsqlgc3nc9)#ngwsmt9q",
        "hex": "0014d3809155e577c27640744abe00c88f683727401f",
        "address": "bcrt1q6wqfz409wlp8vsr5f2lqpjy0dqmjwsqlgc3nc9",
        "type": "witness_v0_keyhash"
      }
    },
    {
      "value": 29.99998590,
      "n": 1,
      "scriptPubKey": {
        "asm": "0 b10ed7d35339191a3023bb7ee66d16d01abccb35",
        "desc": "addr(bcrt1qky8d056n8yv35vprhdlwvmgk6qdteje4p9a8g0)#wyn30jxp",
        "hex": "0014b10ed7d35339191a3023bb7ee66d16d01abccb35",
        "address": "bcrt1qky8d056n8yv35vprhdlwvmgk6qdteje4p9a8g0",
        "type": "witness_v0_keyhash"
      }
    }
  ],
  "hex": "020000000001011144d8fe6053ef6c575ea60c32d02f3e02570569cbea4b7f05ac94aa4af51d6a0000000000fdffffff020094357700000000160014d3809155e577c27640744abe00c88f683727401f7e58d0b200000000160014b10ed7d35339191a3023bb7ee66d16d01abccb350247304402206e01039901a5452e15b47b8a19aaf88e451629832e8489c7cfb0fe2d5ad434d4022073cb43c25f94f86bce413f1644c3eecfbf8efb575ac8018e1536833446553d6a012102b4ff64dd5c438a603d09f4fe760ee6cbe913a42bfb1bf0656bfea2e321ae0d4766000000",
  "blockhash": "1f164136ae3368cbdd110b78acc8d8afb734868ce1b0b4b7c8d9494f8f3d72eb",
  "confirmations": 1,
  "time": 1751919425,
  "blocktime": 1751919425
}
bitcoin-cli "-rpcwallet=Miner" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.txid'
3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Miner" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.amount'-20.00000000
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Trader" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.amount'
20.00000000
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Trader" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.details[] | .address'
bcrt1q6wqfz409wlp8vsr5f2lqpjy0dqmjwsqlgc3nc9
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Trader" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.blockheight'
103
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Trader" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.fee'
null
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Miner" gettransaction "3bdb1367fcaf27b533fdd524a1569de6363d8380cdf171392a660a17fc3aa8b9" | jq -r '.fee'
-0.00001410
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Miner" getbalance
129.99998590
ubuntu@ubuntu-OptiPlex-390:~$ bitcoin-cli "-rpcwallet=Trader" getbalance
20.00000000



