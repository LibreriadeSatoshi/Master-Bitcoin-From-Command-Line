# Semana 2: Demostración Replace-By-Fee (RBF)

**Taller**: Master Bitcoin From Command Line  
**Organización**: Librería de Satoshi  
**Autor**: wizard_latino

## Enlace al Ejercicio Oficial
📖 [Ejercicio Semana 2 - GitHub](https://github.com/LibreriadeSatoshi/Master-Bitcoin-From-Command-Line/blob/main/ejercicios/semana2/ejercicio.md)

## Descripción del Ejercicio

Este ejercicio demuestra el mecanismo **Replace-By-Fee (RBF)** y su impacto en transacciones child.

### Objetivos:
1. Demostrar flujos de trabajo de billeteras Bitcoin usando `bitcoin-cli`
2. Ilustrar el mecanismo Replace-By-Fee (RBF)
3. Mostrar cómo RBF impacta las transacciones child

### Conceptos Cubiertos:
- **Replace-By-Fee (RBF)**: Reemplazo de transacciones no confirmadas
- **Child-Pays-for-Parent (CPFP)**: Aceleración de transacciones parent
- **Conflicto RBF vs CPFP**: Por qué son técnicas mutuamente excluyentes

## Scripts del Ejercicio

| Script | Propósito |
|--------|-----------|
| `semana2.sh` | Script principal |
| `setup_bitcoin.sh` | Configuración Bitcoin Core |
| `manage_wallets.sh` | Gestión de billeteras |
| `rbf_demo.sh` | Demostración RBF |
| `clean_bitcoin.sh` | Limpieza de entorno |

## Instrucciones de Ejecución

### Ejecutar el Ejercicio:
```bash
# Verificar dependencias
which jq bc wget tar

# Acceder a la carpeta del ejercicio
cd <nombre-de-la-carpeta>

# Ejecutar
./semana2.sh
```

### Para Re-ejecutar:

> **Nota**: El script se puede ejecutar perfectamente sin necesidad de limpiar previamente. Los cálculos se realizarán en base a los datos existentes actualmente. El script soporta tanto el escenario de una base de datos vacía como una con datos preexistentes.

```bash
# Para testing iterativo (recomendado):
./clean_bitcoin.sh -y && ./semana2.sh  # Limpiar solo datos + ejecutar (RÁPIDO)
./semana2.sh                           # Ejecutar sin limpiar

# Para empezar desde cero:
./clean_bitcoin.sh -y -f && ./semana2.sh  # Limpieza completa + ejecutar
./semana2.sh --clean                      # Limpieza completa + ejecutar
```

### Script de Limpieza:
```bash
# Menú interactivo para elegir tipo de limpieza
./clean_bitcoin.sh

# Ver opciones de limpieza disponibles
./clean_bitcoin.sh --help
```

## Flujo del Ejercicio

1. **Crear billeteras "Miner" y "Trader"**
2. **Fondear billetera Miner con 150 BTC**
3. **Crear transacción "Parent" con RBF habilitado**
   - 2 inputs de 50 BTC → 70 BTC para Trader + cambio
4. **Crear JSON con detalles de transacción**
5. **Crear transacción "Child" que gasta el cambio (CPFP)**
6. **Ejecutar RBF incrementando fee en 10,000 satoshis**
7. **Observar cómo RBF invalida la transacción Child**

## Resultados de Aprendizaje

Al completar este ejercicio entenderás:
- Cómo funciona Replace-By-Fee (RBF)
- Cómo funciona Child-Pays-for-Parent (CPFP)  
- Por qué RBF y CPFP son mutuamente excluyentes
- El impacto de RBF en transacciones dependientes

## Requisitos Técnicos

### Sistema:
- Linux/Ubuntu (contenedor Docker recomendado)
- Dependencias: `jq`, `bc`, `wget`, `tar`
- ~200MB de espacio para Bitcoin Core
- **Nota**: Los scripts no usan `sudo` ya que están pensados para entornos Docker con privilegios administrativos (root)

### El ejercicio configura automáticamente:
- Descarga Bitcoin Core v29.0
- Configura entorno regtest  
- Crea billeteras temporales para la demostración

---

