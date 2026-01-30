### CURSO Master-bitcoin ####
## Learning from the Command Line ##
## EJERCICIO 1 ##

# Descarga bitcoin core

clear

wget https://bitcoincore.org/bin/bitcoin-core-29.0/bitcoin-29.0-x86_64-linux-gnu.tar.gz

# Descarga firmas

wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS

wget https://bitcoincore.org/bin/bitcoin-core-29.0/SHA256SUMS.asc

# Verifica 


Verify=$(sha256sum --ignore-missing --check SHA256SUMS)

clear

echo Verify

git clone https://github.com/bitcoin-core/guix.sigs

gpg --import guix.sigs/builder-keys/*

SignatureOk=$(gpg --verify SHA256SUMS.asc)

clear

echo SignatureOk

#Descomprimo

tar xzf bitcoin-29.0-x86_64-linux-gnu.tar.gz

# Instalo bitcoin core

sudo install -m 0755 -o root -g root -t /usr/local/bin bitcoin-29.0/bin/*

#Creo directorio .bitcoin y archivo bitcoin.conf

mkdir .bitcoin

cd .bitcoin

cat >> bitcoin.conf <<EOF

regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

clear
