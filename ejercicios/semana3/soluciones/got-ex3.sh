# Configurar Multisig
# Crear tres monederos: Miner, Alice y Bob.
MINERWALLET=MINER7
ALICEWALLET=ALICE7
BOBWALLET=BOB7
MULTIWALLET=MULTI7

#Creating wallets
bitcoin-cli -named createwallet wallet_name=$MINERWALLET passphrase=Contraseña.1

bitcoin-cli -named createwallet wallet_name=$ALICEWALLET passphrase=Contraseña.2

bitcoin-cli -named createwallet wallet_name=$BOBWALLET passphrase=Contraseña.2
bitcoin-cli -named createwallet wallet_name=$MULTIWALLET disable_private_keys=true blank=true


bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 1200
bitcoin-cli -rpcwallet=$ALICEWALLET walletpassphrase "Contraseña.2" 1200
bitcoin-cli -rpcwallet=$BOBWALLET walletpassphrase "Contraseña.2" 1200
#bitcoin-cli -rpcwallet=$MULTIWALLET  1200


# Fondear los monederos generando algunos bloques para Miner y enviando algunas monedas a Alice y Bob.

minerAddress=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "Recompensa de Mineria")
#Minando bloques
bitcoin-cli generatetoaddress 105 "$minerAddress"

#Balance para Miner
balance=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
echo "Balance - Miner wallet: $balance"

# Obtener todos los UTXOs de la billetera
utxos=$(bitcoin-cli -rpcwallet=$MINERWALLET listunspent)

echo $utxos

#Para enviar 80 BTC, usaré los 2 primeros UTXOs de 25 BTC cada uno.

# Extraer los txid y vout de las recompensas en bloque
input1_txid=$(echo "$utxos" | jq -r '.[0].txid')  # Primer UTXO
input1_vout=$(echo "$utxos" | jq -r '.[0].vout')  # Primer UTXO

input2_txid=$(echo "$utxos" | jq -r '.[1].txid')  # Segundo UTXO
input2_vout=$(echo "$utxos" | jq -r '.[1].vout')  # Segundo UTXO

# input3_txid=$(echo "$utxos" | jq -r '.[2].txid')  # Tercer UTXO
# input3_vout=$(echo "$utxos" | jq -r '.[2].vout')  # Tercer UTXO

# input4_txid=$(echo "$utxos" | jq -r '.[3].txid')  # Cuarto UTXO
# input4_vout=$(echo "$utxos" | jq -r '.[4].vout')  # Cuarto UTXO


# Imprimir los valores
echo "Primer UTXO: txid = $input1_txid, vout = $input1_vout"
echo "Segundo UTXO: txid = $input2_txid, vout = $input2_vout"
# echo "Tercer UTXO: txid = $input3_txid, vout = $input3_vout"
# echo "Cuarto UTXO: txid = $input4_txid, vout = $input4_vout"



#Enviando 30 BTC a Bob  y  50 BTC a Alice

# Crear direcciones receptoras con la etiqueta "Recibido" desde las billetreas.
bob_Address=$(bitcoin-cli -rpcwallet=$BOBWALLET getnewaddress "Recibido BOB")
alice_Address=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress "Recibido ALICE")
minerCambio_Address=$(bitcoin-cli -rpcwallet=$MINERWALLET getnewaddress "CambioMiner")


echo "ALICE ADDRESS: $alice_Address"
echo "BOB ADDRESS: $bob_Address"
echo "MINERCAMBIO ADDRESS: $minerCambio_Address"

echo "Creando la transacción"
raw_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET createrawtransaction \
  "[{\"txid\": \"$input1_txid\", \"vout\": $input1_vout, \"sequence\": 0}, \
    {\"txid\": \"$input2_txid\", \"vout\": $input2_vout, \"sequence\": 0}]" \
    "{\"${bob_Address}\": 30, \
      \"${alice_Address}\": 50, \
      \"${minerCambio}\": 19.99999}" \
     )

# Firmar la transacción
bitcoin-cli -rpcwallet=$MINERWALLET walletpassphrase "Contraseña.1" 120
signed_tx=$(bitcoin-cli -rpcwallet=$MINERWALLET signrawtransactionwithwallet "$raw_tx" | jq -r .hex)

# Enviar la transacción firmada a la red
txidEnviada=$(bitcoin-cli sendrawtransaction "$signed_tx")

echo "TxID de la transacción enviada: $txidEnviada"

#Minando un bloque para confirmar transacciones.
bitcoin-cli generatetoaddress 1 "$minerAddress"


#Balance para Miner
balance_miner=$(bitcoin-cli -rpcwallet=$MINERWALLET getbalance)
balance_bob=$(bitcoin-cli -rpcwallet=$BOBWALLET getbalance)
balance_alice=$(bitcoin-cli -rpcwallet=$ALICEWALLET getbalance)

echo "Balance - Miner wallet: $balance_miner"
echo "Balance - Alice wallet: $balance_bob"
echo "Balance - Bob wallet: $balance_alice"


# Crear un wallet Multisig 2-de-2 combinando los descriptors de Alice y Bob. Uilizar la funcion "multi" wsh(multi(2,descAlice,descBob) para crear un "output descriptor". Importar el descriptor al Wallet Multisig. Generar una direccion.

bob_multifirma_address=$(bitcoin-cli -rpcwallet=$BOBWALLET getnewaddress)
alice_multifirma_address=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress)

bob_pubkey=$(bitcoin-cli -rpcwallet=$BOBWALLET -named getaddressinfo address=$bob_multifirma_address | jq -r '.pubkey')

alice_pubkey=$(bitcoin-cli -rpcwallet=$ALICEWALLET -named getaddressinfo address=$alice_multifirma_address | jq -r '.pubkey')

echo "bob_pubkey: $bob_pubkey"
echo "alice_pubkey: $alice_pubkey"


ext_alice_xpub=$(bitcoin-cli  -rpcwallet=$ALICEWALLET listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')
ext_bob_xpub=$(bitcoin-cli -rpcwallet=$BOBWALLET   listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/0/*")).desc' | grep -Po '(?<=\().*(?=\))')
int_alice_xpub=$(bitcoin-cli  -rpcwallet=$ALICEWALLET listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')
int_bob_xpub=$(bitcoin-cli  -rpcwallet=$BOBWALLET   listdescriptors | jq -r '.descriptors[] | select(.desc|startswith("wpkh") and contains("/1/*")).desc' | grep -Po '(?<=\().*(?=\))')

external_descriptor=$(bitcoin-cli getdescriptorinfo "wsh(multi(2,$ext_alice_xpub,$ext_bob_xpub))" | jq -r '.descriptor')
internal_descriptor=$(bitcoin-cli getdescriptorinfo "wsh(multi(2,$int_alice_xpub,$int_bob_xpub))" | jq -r '.descriptor')

descriptors=$(jq -n "[\
  {\"desc\":\"$external_descriptor\",\"active\":true,\"internal\":false,\"timestamp\":\"now\"},\
  {\"desc\":\"$internal_descriptor\",\"active\":true,\"internal\":true,\"timestamp\":\"now\"}\
]")

bitcoin-cli -rpcwallet=$MULTIWALLET importdescriptors "$descriptors"

multi_firma_address=$(bitcoin-cli -rpcwallet=$MULTIWALLET getnewaddress)  # Primera dirección multisig


# echo "Dirección multisig 2-de-2: $multi_firma"

# multi_firma_address=$(echo $multi_firma | jq -r '.address')
#multi_firma_redeemScript=$(echo $multi_firma | jq -r '.redeemScript')
#multi_firma_descriptor=$(echo $multi_firma | jq -r '.descriptor')

echo "multi_firma_address: $multi_firma_address"
#echo "multi_firma_redeemScript: $multi_firma_redeemScript"
#echo "multi_firma_descriptor: $multi_firma_descriptor"

echo "*******CREANDO TRANSACCION PSBT*******"

# Crear una Transacción Bitcoin Parcialmente Firmada (PSBT) para financiar la dirección multisig con 20 BTC, tomando 10 BTC de Alice y 10 BTC de Bob, y proporcionando el cambio correcto a cada uno de ellos.
# Obtener los UTXOs de Alice y Bob
alice_utxos=$(bitcoin-cli -rpcwallet=$ALICEWALLET listunspent)
bob_utxos=$(bitcoin-cli -rpcwallet=$BOBWALLET listunspent)

echo $alice_utxos
echo $bob_utxos


# Extraer los txid y vout de los UTXOs de Alice y Bob
alice_input_txid=$(echo "$alice_utxos" | jq -r '.[0].txid')  # Primer UTXO de Alice
alice_input_vout=$(echo "$alice_utxos" | jq -r '.[0].vout')  # Primer UTXO de Alice
bob_input_txid=$(echo "$bob_utxos" | jq -r '.[0].txid')  # Primer UTXO de Bob
bob_input_vout=$(echo "$bob_utxos" | jq -r '.[0].vout')  # Primer UTXO de Bob
echo "Alice Input: txid = $alice_input_txid, vout = $alice_input_vout"
echo "Bob Input: txid = $bob_input_txid, vout = $bob_input_vout"


# Crear la transacción raw

amount_to_send=20.0
bob_change_address=$(bitcoin-cli -rpcwallet=$BOBWALLET getnewaddress)
alice_change_address=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress)

# Crear PSBT y firmar con ambos

rawtxhex=$(bitcoin-cli  -named createpsbt inputs='''[
  { "txid": "'$alice_input_txid'", "vout": '$alice_input_vout' },
  { "txid": "'$bob_input_txid'", "vout": '$bob_input_vout' }
]''' outputs='''{
  "'$multi_firma_address'": '''$amount_to_send''',
  "'$alice_change_address'": 39.9999,
  "'$bob_change_address'": 19.9999
}''')


echo "Transacción multifirma raw: $rawtxhex"

signed_by_alice_tx=$(bitcoin-cli -rpcwallet=$ALICEWALLET walletprocesspsbt "$rawtxhex" | jq -r '.psbt')

signed_by_bob_tx=$(bitcoin-cli -rpcwallet=$BOBWALLET   walletprocesspsbt "$signed_by_alice_tx" | jq -r '.psbt')

tx_finalizada=$(bitcoin-cli finalizepsbt "$signed_by_bob_tx" | jq -r '.hex')  
tx=$(bitcoin-cli -rpcwallet=$MULTIWALLET sendrawtransaction "$tx_finalizada")           

# Confirmar el saldo mediante la minería de algunos bloques adicionales.
bitcoin-cli generatetoaddress 1 "$minerAddress"

final_balance_alice=$(bitcoin-cli -rpcwallet=$ALICEWALLET getbalance)
final_balance_bob=$(bitcoin-cli -rpcwallet=$BOBWALLET getbalance)
final_balance_multi=$(bitcoin-cli -rpcwallet=$MULTIWALLET getbalance)


# Obtener los saldos finales de Alice y Bob.
echo "Saldo final de Alice: $final_balance_alice"
echo "Saldo final de Bob: $final_balance_bob"
echo "Saldo final de Multi wallet: $final_balance_multi"



#***********************************SEGUNDA PARTE******************************************++
# Crear una PSBT para gastar fondos del wallet Multisig, enviando 3 BTC a Alice. Genera una direccion de cambio desde el wallet Multisig

alice_Address2=$(bitcoin-cli -rpcwallet=$ALICEWALLET getnewaddress "Recibido ALICE de Multifirma")

# Direccion de cambio de la multifirma

bitcoin-cli -rpcwallet=$MULTIWALLET importdescriptors "$descriptors"

multisig_change_addr=$(bitcoin-cli -rpcwallet=$MULTIWALLET deriveaddresses "$internal_descriptor" "[0,1]" | jq -r '.[1]')  # Primera dirección multisig



multi_utxos=$(bitcoin-cli -rpcwallet=$MULTIWALLET listunspent)
echo $multi_utxos

# Extraer los txid y vout de las recompensas en bloque
multi_input1_txid=$(echo "$multi_utxos" | jq -r '.[0].txid')  # Primer UTXO
multi_input1_vout=$(echo "$multi_utxos" | jq -r '.[0].vout')  # Primer UTXO
multi_input1_scriptPubKey=$(echo "$multi_utxos" | jq -r '.[0].scriptPubKey')  # Primer UTXO

echo "multi_input1_txid $multi_input1_txid"
echo "multi_input1_vout $multi_input1_vout"
echo "multi_input1_scriptPubKey $multi_input1_scriptPubKey"



psbt_tx2=$(bitcoin-cli  -named createpsbt inputs='''[
  { "txid": "'$multi_input1_txid'", "vout": '$multi_input1_vout' } 
]''' outputs='''{
  "'$multisig_change_addr'": 16.9999,
  "'$alice_Address2'": 3
}''')


signed_by_multi_tx=$(bitcoin-cli -rpcwallet=$MULTIWALLET walletprocesspsbt "$psbt_tx2" | jq -r '.psbt')

signed_by_alice_tx=$(bitcoin-cli -rpcwallet=$ALICEWALLET walletprocesspsbt "$signed_by_multi_tx" | jq -r '.psbt')
signed_by_bob_tx=$(bitcoin-cli -rpcwallet=$BOBWALLET walletprocesspsbt "$signed_by_alice_tx" | jq -r '.psbt')
tx_finalizada=$(bitcoin-cli  finalizepsbt "$signed_by_bob_tx")
tx_finalizada_hex=$(echo "$tx_finalizada" | jq -r '.hex')
#Enviando TX
txid3=$(bitcoin-cli  sendrawtransaction "$tx_finalizada_hex")


# Confirmar el saldo mediante la minería de algunos bloques adicionales.
bitcoin-cli generatetoaddress 1 "$minerAddress"

final_balance_alice=$(bitcoin-cli -rpcwallet=$ALICEWALLET getbalance)
final_balance_bob=$(bitcoin-cli -rpcwallet=$BOBWALLET getbalance)
final_balance_multi=$(bitcoin-cli -rpcwallet=$MULTIWALLET getbalance)


# Obtener los saldos finales de Alice y Bob.
echo "Saldo final de Alice: $final_balance_alice"
echo "Saldo final de Bob: $final_balance_bob"
echo "Saldo final de Multi wallet: $final_balance_multi"


# Mostrar el TXID de la transacción finalizada
echo "TXID de la transacción finalizada: $txid3"
# Mostrar los detalles de la transacción finalizada
bitcoin-cli -rpcwallet=$MULTIWALLET gettransaction "$txid3"
# Mostrar los detalles de la transacción finalizada
echo "Detalles de la transacción finalizada:"
bitcoin-cli -rpcwallet=$MULTIWALLET gettransaction "$txid3" | jq '. | {txid: .txid, details: .details, amount: .amount, fee: .fee, confirmations: .confirmations, blockhash: .blockhash}'
