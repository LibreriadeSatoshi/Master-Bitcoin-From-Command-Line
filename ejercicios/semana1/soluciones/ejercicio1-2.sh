# Arranco bitcoin core #

bitcoind -daemon
bitcoin-cli getblockchaininfo

echo "Arranque"

# CREAR BILLETERAS #

echo "Crea billeteras"

cd regtest
cd wallets


bitcoin-cli createwallet "Miner"
bitcoin-cli createwallet "Trader"
# wallets=$(bitcoin-cli listwallets)

echo  wallets

# Crear direccion para MINER #

bitcoin-cli -rpcwallet=Miner getnewaddress  "Recompensa de mineria"

bitcoin-cli generatetoaddress 101 "bcrt1q2tqtgvfmmwuwk3xl29kqqcdmeel7xajx2wcag2"

echo "Hay que minar al menos 101 bloques en regtest para que las recompensas por bloque puedan ser gastadas (por la regla de madurez de coinbase: 100 bloques)"

bitcoin-cli -rpcwallet=Miner getbalance

# Direccion receptora #

bitcoin-cli -rpcwallet=Trader getnewaddress  "Recibido"

#Transaccion #

bitcoin-cli rpcwallet=Miner sendtoaddress "bcrt1qty3q8xpzx34j05nuj0nyermdvg53kn7tkuajd8" 20

# Obtener la transaccion desde el mempool #

bitcoin-cli getmempoolentry "a74c652864934e0a5210ea33c9e64764002b11dc025eb190eb237ad00b6a6e70"

# Genero un bloque mas #

bitcoin-cli generatetoaddress 1 "bcrt1qpeeyd6n25dt80uwl7clvcf2s4ymtwx2e00slev"

# Datos de la transaccion #

bitcoin-cli -rpcwallet=Miner gettransaction "a74c652864934e0a5210ea33c9e64764002b11dc025eb190eb237ad00b6a6e70"

bitcoin-cli -rpcwallet=Miner decoderawtransaction $(bitcoin-cli getrawtransaction "a74c652864934e0a5210ea33c9e64764002b11dc025eb190eb237ad00b6a6e70")
