#!/bin/bash
export PATH="$PWD/bitcoin-30.2/bin:$PATH"
rm -rf ~/.bitcoin/regtest/
./bitcoin-30.2/bin/bitcoind -daemon
sleep 3

#### Configurar un contrato

# 1. Crea varios wallets y un wallet Miner
alias bitcoin-cli="bitcoin-30.2/bin/bitcoin-cli -regtest -rpcuser=usuario -rpcpassword=contraseña"
bitcoin-cli createwallet Miner &&> /dev/null
bitcoin-cli loadwallet Miner &> /dev/null
bitcoin-cli createwallet Alice &> /dev/null
bitcoin-cli loadwallet Alice &> /dev/null
descAliceint=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descAliceext=$(bitcoin-cli -rpcwallet=Alice listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
bitcoin-cli createwallet Bob &> /dev/null
bitcoin-cli loadwallet Bob &> /dev/null
descBobint=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descBobext=$(bitcoin-cli -rpcwallet=Bob listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
bitcoin-cli createwallet Carol &> /dev/null
bitcoin-cli loadwallet Carol &> /dev/null
descCarolint=$(bitcoin-cli -rpcwallet=Carol listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')
descCarolext=$(bitcoin-cli -rpcwallet=Carol listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')


# 2. Con la ayuda del compilador online https://bitcoin.sipa.be/miniscript/ crea un miniscript
# 3. Muestra un mensaje en pantalla explicando como esperas que se comporte el script
echo "El script se comporta de la siguiente manera: Alice puede gastar los fondos con su firma.
Sus herederos Bob y Carol pueden gastar si Alice no gasta pasados 10 bloques, pero ambos deben ponerse de acuerdo para gastar los fondos."
echo "or_i(and_v(v:multi(2,carol,bob),older(10)),pk(alice))"
echo "
      <OP_IF
        2 <carol> <bob> 2 OP_CHECKMULTISIGVERIFY 10 OP_CHECKSEQUENCEVERIFY
      OP_ELSE
        <alice> OP_CHECKSIG
      OP_ENDIF"
# 4. Crea el descriptor para ese miniscript.
echo "Creando descriptor para el miniscript..."
descext="wsh(or_i(and_v(v:multi(2,$descCarolext,$descBobext),older(10)),pk($descAliceext)))"
descint="wsh(or_i(and_v(v:multi(2,$descCarolint,$descBobint),older(10)),pk($descAliceint)))"
descextsum=$(bitcoin-cli getdescriptorinfo $descext | jq -r '.descriptor')
intdescsum=$(bitcoin-cli getdescriptorinfo $descint | jq -r '.descriptor')

# 5. Crea un nuevo wallet, importa el descriptor y genera una dirección.
echo "Creando wallet miniscript..."
bitcoin-cli -named createwallet wallet_name="miniscript" disable_private_keys=true blank=true &> /dev/null

echo "Importando descriptor en el wallet miniscript..."
bitcoin-cli -rpcwallet=miniscript importdescriptors "[{\"desc\": \"$descextsum\", \"active\": true,\"timestamp\": \"now\", \"internal\": false, \"range\": [0,100]}, {\"desc\": \"$intdescsum\", \"active\": true,\"timestamp\": \"now\", \"internal\": true, \"range\": [0,100] }]"
echo "loadwallet miniscript..."
bitcoin-cli loadwallet miniscript &> /dev/null

# 6. Envia unos BTC a la dirección desde Miner
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Recompensa de Mineria")
bitcoin-cli generatetoaddress 101 "$miner_address" &> /dev/null
echo "enviando fondos a la dirección del miniscript..."
miniscript_address=$(bitcoin-cli -rpcwallet=miniscript getnewaddress)
echo "Dirección del miniscript: $miniscript_address"
bitcoin-cli -rpcwallet=Miner sendtoaddress $miniscript_address 10
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null
echo "Saldo en wallet miniscript: $(bitcoin-cli -rpcwallet=miniscript getbalance)"

#### Gastar desde la dirección
# 1. Elige de los posibles caminos de gasto uno, si es necesario crea los wallets con la combinación de claves privadas y publicas.
echo "Gastar desde la dirección usando el camino de Alice"
miniscript_utxo=$(bitcoin-cli -rpcwallet=miniscript listunspent | jq '.[0]')
miniscript_txid=$(echo "$miniscript_utxo" | jq -r '.txid')
miniscript_vout=$(echo "$miniscript_utxo" | jq -r '.vout')
miniscript_amount=$(echo "$miniscript_utxo" | jq -r '.amount')
echo "UTXO a gastar: $miniscript_txid:$miniscript_vout con monto $miniscript_amount"
alice_address=$(bitcoin-cli -rpcwallet="Alice" getnewaddress)
miniscript_change_address=$(bitcoin-cli -rpcwallet="miniscript" getrawchangeaddress)
change_amount=$(echo "$miniscript_amount - 1 - 0.00001" | bc)
inputs="[{\"txid\": \"$miniscript_txid\", \"vout\": $miniscript_vout, \"sequence\": 0}]"
outputs="[{\"$alice_address\": 1}, {\"$miniscript_change_address\": $change_amount}]"
psbt=$(bitcoin-cli -rpcwallet=miniscript createpsbt "$inputs" "$outputs")
psbt=$(bitcoin-cli -rpcwallet=miniscript walletprocesspsbt "$psbt" | jq -r '.psbt')
alice_psbt=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt "$psbt" | jq -r '.psbt')
bob_psbt=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$alice_psbt" | jq -r '.psbt')
updated_psbt=$(bitcoin-cli -rpcwallet=miniscript walletprocesspsbt "$bob_psbt"| jq -r '.psbt')
final_hex=$(bitcoin-cli -rpcwallet=miniscript finalizepsbt "$updated_psbt" | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction "$final_hex")
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null
echo "Alice puede gastar cuando quiera: $(bitcoin-cli -rpcwallet=Alice getbalance)"

# 2. Gasta de la dirección. Si tiene bloqueo de tiempo demuestra que no se puede gastar antes del tiempo.
bitcoin-cli generatetoaddress 10 "$miner_address" &> /dev/null
echo "Gastar desde la dirección usando el camino de Bob y Carol"
miniscript_utxo=$(bitcoin-cli -rpcwallet=miniscript listunspent | jq '.[0]')
miniscript_txid=$(echo "$miniscript_utxo" | jq -r '.txid')
miniscript_vout=$(echo "$miniscript_utxo" | jq -r '.vout')
miniscript_amount=$(echo "$miniscript_utxo" | jq -r '.amount')
echo "UTXO a gastar: $miniscript_txid:$miniscript_vout con monto $miniscript_amount"
bob_address=$(bitcoin-cli -rpcwallet="Bob" getnewaddress)
carol_address=$(bitcoin-cli -rpcwallet="Carol" getnewaddress)
miniscript_change_address=$(bitcoin-cli -rpcwallet="miniscript" getrawchangeaddress)
change_amount=$(echo "$miniscript_amount - 2 - 0.00001" | bc)
inputs="[{\"txid\": \"$miniscript_txid\", \"vout\": $miniscript_vout, \"sequence\": 10}]"
outputs="[{\"$bob_address\": 1}, {\"$carol_address\": 1}, {\"$miniscript_change_address\": $change_amount}]"
psbt=$(bitcoin-cli -rpcwallet=miniscript createpsbt "$inputs" "$outputs")
psbt=$(bitcoin-cli -rpcwallet=miniscript walletprocesspsbt "$psbt" | jq -r '.psbt')
bob_psbt=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt "$psbt" | jq -r '.psbt')
carol_psbt=$(bitcoin-cli -rpcwallet=Carol walletprocesspsbt "$bob_psbt" | jq -r '.psbt')
updated_psbt=$(bitcoin-cli -rpcwallet=miniscript walletprocesspsbt "$carol_psbt"| jq -r '.psbt')
final_hex=$(bitcoin-cli -rpcwallet=miniscript finalizepsbt "$updated_psbt" | jq -r '.hex')
txid=$(bitcoin-cli sendrawtransaction "$final_hex")
bitcoin-cli generatetoaddress 1 "$miner_address" &> /dev/null
echo "Bob y Carol pueden gastar después de 10 bloques: $(bitcoin-cli -rpcwallet=Bob getbalance), $(bitcoin-cli -rpcwallet=Carol getbalance)"

bitcoin-cli stop
