#!/usr/bin/env bash


#Script ejercicio de la semana 1 del curso Master Bitcoin From Command Line
###################################################################################

#Salir si un comando falla
set -e

###################################################################################

#Funcion para pedir confirmación al usuario
confirm() {
	while true; do
		read -p "$1 (s/n): " yn
		case $yn in
			[Ss]* ) return 0;; #Para aceptar (s o S)
			[Nn]* ) echo "Saliendo..."; exit 1;; # Salir (n o N)
			* ) echo "Por favor responde con s o n";;
		esac
	done
}

###################################################################################

#Configuración
NEW_USER="regtest"
USER_ADMIN="${SUDO_USER:-$USER}"
USER_HOME="/home/$NEW_USER"
BTC_DIR="$USER_HOME/.bitcoin"
DATA_DIR="/data/regtest"
BTC_CONF="$BTC_DIR/bitcoin.conf"
SERVICE_FILE="/etc/systemd/system/bitcoind.service"
SERVICE_NAME="bitcoind -regtest -daemon"
BTC_VERSION="29.0"
BTC_EXT_DIR="bitcoin-${BTC_VERSION}"
BTC_TAR="bitcoin-${BTC_VERSION}-x86_64-linux-gnu.tar.gz"
BTC_URL="https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/${BTC_TAR}"
SHA256SUMS_URL="https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/SHA256SUMS"
SHA256SUMS_ASC_URL="https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/SHA256SUMS.asc"

###################################################################################

#Funcion para verificar si eres root
echo "Verificando privilegios de root..."
if [[ $EUID -ne 0 ]]; then
  echo "Este script debe ser ejecutado como root. Use sudo."
  exit 1
fi

###################################################################################

#Actualizar e instalar dependencias 
echo "Actualizando e instalando las dependencias..."
confirm "¿Quieres continuar?"

apt-get update && apt-get full-upgrade -y
apt-get install -y git curl wget gnupg jq python3 ca-certificates nano tar sudo net-tools iputils-ping

###################################################################################

#Cambio al directorio tmp para una instalación limpia
cd /tmp

###################################################################################

#Descarga de Binarios y demás archivos
echo "¿Quieres descargar Bitcoin Core versión = ${BTC_VERSION}?"
confirm "¿Quieres continuar?"

#Descarga el archivo tar
wget -q $BTC_URL -O $BTC_TAR

#Descarga de la lista de comprobación criptográfica
wget -q $SHA256SUMS_URL -O SHA256SUMS

#Descarga de las firmas para comprobar las sumas de comprobación
wget -q $SHA256SUMS_ASC_URL -O SHA256SUMS.asc

###################################################################################

#Verificar la suma SHA256 de comprobación
echo "¿Verificamos la suma SHA256 de comprobación?"
confirm "¿Quieres continuar?"

sha256sum --ignore-missing --check SHA256SUMS || {
echo "Fallo en verificación SHA256... Saliendo"
	exit 1
}

echo "¡Éxito en la verificación del SHA256!"

###################################################################################

#Descarga de base de datos de claves GPG
echo "¿Quieres descargar la base de datos de claves GPG?"
confirm "¿Quieres continuar?"

curl -s "https://api.github.com/repositories/355107265/contents/builder-keys" | grep download_url | grep -oE "https://[a-zA-Z0-9./-]+" | while read url; do 
    curl -s "$url" | gpg --import; 
done

###################################################################################

#Verificación de firma criptográfica con claves del archivo de sumas de comprobación

gpg --verify SHA256SUMS.asc SHA256SUMS || {
	echo "Fallo en verificación de firma GPG... Saliendo"
	exit 1
}

echo "¡Éxito al verificar Firma GPG!"

###################################################################################

#Extraer binarios e instalación
echo "¿Quiere comenzar la extracción de binarios para su instalación?"
confirm "¿Quieres continuar?"

tar -xf "$BTC_TAR"
install -m 0755 -o root -g root -t /usr/local/bin "$BTC_EXT_DIR/bin/"*

echo "¡Éxito al instalar los binarios de Bitcoin Core!"

###################################################################################

#Creación del usuario 
echo "¿Quiere crear el nuevo usuario Regtest?"
confirm "¿Quieres continuar?"

adduser --gecos "" --disabled-password $NEW_USER

###################################################################################

#Creacion del directorio de datos
echo "¿Quiere crear un directorio de datos?"
confirm "¿Quieres continuar?"

mkdir -p "$DATA_DIR"
chown "$NEW_USER:$NEW_USER" "$DATA_DIR"

###################################################################################

# Descargar rpcauth.py y generar credenciales como regtest
sudo -u "$NEW_USER" bash <<EOSU
set -e

USER_HOME="/home/$NEW_USER"
RCP_USER="$NEW_USER"

cd \$USER_HOME
mkdir -p .bitcoin
cd .bitcoin

wget -q https://raw.githubusercontent.com/bitcoin/bitcoin/master/share/rpcauth/rpcauth.py

RPC_OUTPUT=\$(python3 rpcauth.py "\$RCP_USER")
RPC_AUTH=\$(echo "\$RPC_OUTPUT" | grep -oP '(?<=rpcauth=)\S+')
RPC_PASS=\$(echo "\$RPC_OUTPUT" | awk '/Your password:/ {getline; print \$1}' | tr -d '[:space:]')

echo "rpcauth generado:"
echo "\$RPC_AUTH"
echo "Password temporal: \$RPC_PASS" > ~/rpc_password.txt
echo "Guarda esta contraseña, está en ~/rpc_password.txt"

# Crear enlace simbólico desde ~/.bitcoin -> /data/regtest
ln -sf /data/regtest/regtest ~/.bitcoin/regtest

# Crear archivo bitcoin.conf
cat <<EOF > ~/.bitcoin/bitcoin.conf
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

chmod 640 ~/.bitcoin/bitcoin.conf
EOSU

###################################################################################

# Crear servicio systemd
echo "Crear servicio systemd"
confirm "¿Quieres continuar?"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Bitcoin Daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/bitcoind -daemon -conf=$BTC_CONF -datadir=$DATA_DIR
ExecStop=/usr/local/bin/bitcoin-cli -conf=$BTC_CONF stop
User=$NEW_USER
Restart=on-failure
Type=forking

[Install]
WantedBy=multi-user.target
EOF

###################################################################################

# Habilitar y arrancar el servicio (SI NO USA DOCKER HABILITELO)
#systemctl daemon-reload
#systemctl enable "$SERVICE_NAME"
#systemctl start "$SERVICE_NAME"

#echo "Servicio $SERVICE_NAME habilitado y arrancado."
#echo "Instalación de Bitcoin Core completa en modo regtest."

###################################################################################

echo "Iniciando bitcoind como servicio en segundo plano (modo regtest)"
confirm "¿Quieres continuar?"

sudo -u "$NEW_USER" /usr/local/bin/bitcoind -daemon -conf="$BTC_CONF" -datadir="$DATA_DIR"

echo "bitcoind se está ejecutando en segundo plano como $NEW_USER"

echo "Verificando estado del nodo..."
sleep 2
sudo -u "$NEW_USER" /usr/local/bin/bitcoin-cli -conf="$BTC_CONF" -datadir="$DATA_DIR" getblockchaininfo

###################################################################################

echo "Cambiando al usuario regtest para iniciar el siguiente script"
confirm "¿Cambiamos de usuario?"

SCRIPT_PATH="/home/$USER_ADMIN/Semana1_SvenS101/Ejercicio1_SvenS101.sh"

chmod -R o+rX "$(dirname "$SCRIPT_PATH")"
sudo su - regtest -c "bash $SCRIPT_PATH"
