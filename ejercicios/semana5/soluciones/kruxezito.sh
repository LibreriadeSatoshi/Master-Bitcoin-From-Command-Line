#!/bin/bash

#-----------COPIE MI INICIALIZACION DEL BITCOIND-----------

btr_cli="bitcoin-cli -conf=$HOME/.bitcoin/bitcoin.conf"

# Stop a Bitcoind para no tener problema al inicialiarlo.
$btr_cli stop &> /dev/null

sleep 3

# Remove a Regtest para Comenzar desde 0.
if [[ "$OSTYPE" == "darwin"* ]]; then
    rm -rf ~/Library/Application\ Support/Bitcoin/regtest
else
    rm -rf ~/.bitcoin/regtest/ &> /dev/null
fi

# Inicializando Bitcoind --daemon.
bitcoind -conf="$HOME/.bitcoin/bitcoin.conf" --daemon

sleep 5

# ======================================================
# CONFIGURAR UN CONTRATO.
# ======================================================

# 1. Crea varios wallets y un Miner.
wallets=("Miner" "Alice" "Bob")
for wallet in ${wallets[@]}; do
    $btr_cli createwallet $wallet &> /dev/null || $btr_cli loadwallet $wallet &> /dev/null 
done

#----Crear y fondear Miner address
miner_address=$($btr_cli -rpcwallet=Miner getnewaddress)
$btr_cli generatetoaddress 101 "$miner_address" &> /dev/null

# 2. Con la ayuda del compilador online https://bitcoin.sipa.be/miniscript/ crea un miniscript.
# Mi politica de gasto Miniscript: thresh(2, pk(Alice), pk(Bob), older(144))

# 3. Muestra un mensaje en pantalla explicando como esperas que se comporte el script. 

echo "##################################################" 
echo "CONTRATO DE CUSTODIA INTELIGENTE (MINISCRIPTS)"
echo "--------------------------------------------------"
echo "Este script implementa una Boveda de Seguridad con 3 rutas de gasto:" 
echo ""
echo "1. RUTA COOPERATIVA (INMEDIATA):"
echo "   - Requiere firmas de Alice Y Bob simultáneamente."
echo "   - Los fondos se mueven al instante (sin esperas)."
echo ""
echo "2. RUTA DE RECUPERACION (POR TIEMPO):"
echo "   - Si un socio falta, el otro puede recuperar los fondos SOLO."
echo "   - RESTRICCIÓN: La red Bitcoin bloqueará el gasto hasta que pasen"
echo "     144 bloques (~24 horas) desde la confirmación del depósito."
echo "" 
echo "##################################################"

alice_desc=$($btr_cli -rpcwallet=Alice listdescriptors | jq -r '
    .descriptors[] | select((.desc 
    | startswith("tr(")) and .internal == false) | .desc 
    | split(")") | .[0] | split("tr(") | .[1] 
    | sub("/0/\\*"; "/<0;1>/*")')

bob_desc=$($btr_cli -rpcwallet=Bob listdescriptors | jq -r '
        .descriptors[] | select((.desc
        | startswith("tr(")) and .internal == false) | .desc
        | split(")") | .[0] | split("tr(") | .[1]
        | sub("/0/\\*"; "/<0;1>/*")')


nums_key="50929b74c1a04954b78b4b6035e97a5e078a5a0f28ec96d547bfee9ace803ac0"

miniscript="thresh(2,pk($alice_desc),s:pk($bob_desc),sln:older(144))"

# 4. Crea el descriptor para ese miniscript
descriptor="tr($nums_key,$miniscript)"
checksum=$($btr_cli getdescriptorinfo "$descriptor" | jq -r '.checksum')
output_descriptor="[{\"desc\": \"$descriptor#$checksum\", \"active\": true, \"timestamp\": \"now\", \"range\": [0,999]}]"

# 5. Crea un nuevo wallet, importa el descriptor y genera una direccion
$btr_cli createwallet Contrato true true &> /dev/null || $btr_cli loadwallet Contrato &> /dev/null
$btr_cli -rpcwallet=Contrato importdescriptors "$output_descriptor" &> /dev/null
contrato_address=$($btr_cli -rpcwallet=Contrato getnewaddress "Address" "bech32m")

# 6. Envia unos BTC a la direccion desde Miner
miner_outpoint=$($btr_cli -rpcwallet=Miner listunspent | jq '.[0] | { txid, vout }')
miner_txid=$(echo $miner_outpoint | jq -r ".txid")
miner_vout=$(echo $miner_outpoint | jq -r ".vout")

raw_tx=$($btr_cli -rpcwallet=Miner createrawtransaction "[{\"txid\":\"$miner_txid\",\"vout\":$miner_vout}]" "{\"$contrato_address\": 49.9999 }")
signed_tx=$($btr_cli -rpcwallet=Miner signrawtransactionwithwallet $raw_tx | jq -r '.hex')
$btr_cli -rpcwallet=Miner sendrawtransaction $signed_tx &> /dev/null
$btr_cli generatetoaddress 1 $miner_address &> /dev/null

miner_balance=$($btr_cli -rpcwallet=Miner getbalance)
alice_balance=$($btr_cli -rpcwallet=Alice getbalance)
bob_balance=$($btr_cli -rpcwallet=Bob getbalance)
contrato_balance=$($btr_cli -rpcwallet=Contrato getbalance)

echo "################### ANTES ###################"
echo "======================================================"
echo "Miner: $miner_balance"
echo "......................................................"
echo "Alice: $alice_balance"
echo "......................................................"
echo "Bob: $bob_balance"
echo "......................................................"
echo "Contrato: $contrato_balance"
echo "======================================================"

# ====================================================== 
# GASTAR DESDE LA DIRECCION.
# ======================================================  

# 1. Elige de los posibles caminos de gasto uno, si es necesario crea los wallets con la combinacion de claves privadas y publicas
contrato_outpoint=$($btr_cli -rpcwallet=Contrato listunspent | jq '.[0] | { txid, vout }')
contrato_txid=$(echo $contrato_outpoint | jq -r ".txid")
contrato_vout=$(echo $contrato_outpoint | jq -r ".vout")

alice_address=$($btr_cli -rpcwallet=Alice getnewaddress)
bob_address=$($btr_cli -rpcwallet=Bob getnewaddress)
contrato_change_address=$($btr_cli -rpcwallet=Contrato getrawchangeaddress "bech32m")

psbt_ruta_inmediata=$($btr_cli createpsbt "[{\"txid\": \"$contrato_txid\", \"vout\": $contrato_vout}]" "[{\"$alice_address\": 20}, {\"$bob_address\": 20}, {\"$contrato_change_address\": 9.9998}]")
contrato_update_psbt=$($btr_cli utxoupdatepsbt "$psbt_ruta_inmediata")
psbtC=$($btr_cli -rpcwallet=Contrato walletprocesspsbt "$contrato_update_psbt" | jq -r '.psbt')                  
psbtA=$($btr_cli -rpcwallet=Alice walletprocesspsbt "$psbtC" | jq -r '.psbt') 
psbtB=$($btr_cli -rpcwallet=Bob walletprocesspsbt "$psbtA" | jq -r '.psbt')
finalizado=$($btr_cli finalizepsbt "$psbtB" | jq -r '.hex')

$btr_cli sendrawtransaction $finalizado &> /dev/null
$btr_cli generatetoaddress 1 $miner_address &> /dev/null

alice_new_address=$($btr_cli -rpcwallet=Alice getnewaddress)
contrato_outpoint2=$($btr_cli -rpcwallet=Contrato listunspent | jq '.[0] | { txid, vout }')
contrato_txid2=$(echo $contrato_outpoint2 | jq -r ".txid")
contrato_vout2=$(echo $contrato_outpoint2 | jq -r ".vout")

# 2. Gasta de la direccion. Si tiene bloqueo de tiempo demuestra que no se puede gastar antes de tiempo.

alice_psbt=$($btr_cli createpsbt "[{\"txid\": \"$contrato_txid2\", \"vout\": $contrato_vout2, \"sequence\": 144}]" "{\"$alice_new_address\": 9.9997}")
contrato_update_psbt2=$($btr_cli utxoupdatepsbt "$alice_psbt")
psbtContrato=$($btr_cli -rpcwallet=Contrato walletprocesspsbt "$contrato_update_psbt2" | jq -r '.psbt')
psbtAlice=$($btr_cli -rpcwallet=Alice walletprocesspsbt "$psbtContrato" | jq -r '.psbt')
alice_psbt_finalizado=$($btr_cli finalizepsbt "$psbtAlice" | jq -r '.hex')

# Ahora intentaremos enviarla y No nos dejara por que aun no se cumple los 144 bloques del OP_CHECKSEQUENCEVERIFY nos dara un error de non-BIP68-final. 
echo -e "\nIntentando gastar por la ruta de recuperación antes de tiempo..."
error_msg=$($btr_cli sendrawtransaction "$alice_psbt_finalizado" 2>&1)
echo "Mensaje de la red: $error_msg"

# 3. Muestra en un mensaje que condicion de gasto se ha cumplido.
echo -e "\nLa condicion de gasto que se efectuo fue la Inmediata (Alice + Bob)."
echo "La ruta de recuperación (Alice solo) falló correctamente debido al bloqueo de tiempo (older)."

# Actualizando balances para el reporte final
miner_balance=$($btr_cli -rpcwallet=Miner getbalance)
alice_balance=$($btr_cli -rpcwallet=Alice getbalance)
bob_balance=$($btr_cli -rpcwallet=Bob getbalance)
contrato_balance=$($btr_cli -rpcwallet=Contrato getbalance)

echo "################### DESPUES ###################"
echo "======================================================"
echo "Miner: $miner_balance"
echo "......................................................"
echo "Alice: $alice_balance"
echo "......................................................"
echo "Bob: $bob_balance"
echo "......................................................"
echo "Contrato: $contrato_balance"
echo "======================================================"
