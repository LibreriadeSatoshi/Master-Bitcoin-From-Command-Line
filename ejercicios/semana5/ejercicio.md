# Enunciado del Problema

En este ejercicio, crea unas condiciones de gasto usando los miniscripts, puedes usar cualquier de las expresiones "and", "or" o "thresh" dentro de los descriptors "wsh" o "tr"

## Escribe un script de bash para:

#### Configurar un contrato

1. Crea varios wallets y un wallet Miner
2. Con la ayuda del compilador online https://bitcoin.sipa.be/miniscript/ crea un miniscript
3. Muestra un mensaje en pantalla explicando como esperas que se comporte el script
4. Crea el descriptor para ese miniscript.
5. Crea un nuevo wallet, importa el descriptor y genera una dirección.
6. Envia unos BTC a la dirección desde Miner

#### Gastar desde la dirección

1. Elige de los posibles caminos de gasto uno, si es necesario crea los wallets con la combinación de claves privadas y publicas.
2. Gasta de la dirección. Si tiene bloqueo de tiempo demuestra que no se puede gastar antes del tiempo.
3. Muestra en un mensaje que condicion de gasto se ha cumplido.

## Entrega
- Crea un script de bash con tu solución para todo el ejercicio.
- Guarda el script en la carpeta de soluciones proporcionada con el nombre `<tu-nombre-en-Discord>.sh`
- Crea una solicitud de pull para agregar el nuevo archivo a la carpeta de soluciones.
- El script debe incluir todos los pasos del ejercicio, pero también puedes agregar mejoras o funcionalidades adicionales a tu script.

## Recursos

- Ejemplos útiles de scripts de bash: https://linuxhint.com/30_bash_script_examples/
- Ejemplos útiles de uso de jq: https://www.baeldung.com/linux/jq-command-json
- Usar jq para crear JSON: https://spin.atomicobject.com/2021/06/08/jq-creating-updating-json/
- Cómo crear una solicitud de extracción a través de un navegador web: [https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request)


