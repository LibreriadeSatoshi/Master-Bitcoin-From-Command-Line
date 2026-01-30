# Semana 3: Demostración Transacciones Multisig

**Taller**: Master Bitcoin From Command Line  
**Organización**: Librería de Satoshi  
**Autor**: wizard_latino

## Enlace al Ejercicio Oficial
📖 [Ejercicio Semana 3 - GitHub](https://github.com/LibreriadeSatoshi/Master-Bitcoin-From-Command-Line/blob/main/ejercicios/semana3/ejercicio.md)

## Descripción del Ejercicio

Este ejercicio demuestra el mecanismo de **transacciones multisig 2-de-2** entre Alice y Bob y el manejo de **PSBT (Partially Signed Bitcoin Transactions)**.

### Objetivos:
1. Demostrar flujos de trabajo de billeteras Bitcoin usando `bitcoin-cli`
2. Ilustrar el mecanismo de direcciones multisig 2-de-2
3. Mostrar creación y firma de PSBT (Partially Signed Bitcoin Transactions)
4. Implementar fondeo y gasto de direcciones multisig

### Conceptos Cubiertos:
- **Multisig 2-de-2**: Direcciones que requieren 2 firmas de 2 claves públicas
- **PSBT**: Transacciones parcialmente firmadas para coordinación entre partes
- **Descriptor Wallets**: Sistema moderno de wallets en Bitcoin Core v29
- **scantxoutset**: Rastreo de UTXOs externos a las wallets

## Scripts del Ejercicio

| Script | Propósito |
|--------|-----------|
| `semana3.sh` | Script principal |
| `setup_bitcoin.sh` | Configuración Bitcoin Core |
| `manage_wallets.sh` | Gestión de billeteras |
| `multisig_demo.sh` | Demostración Multisig con PSBT y comparación Legacy vs Descriptors |
| `clean_bitcoin.sh` | Limpieza de entorno |

## Instrucciones de Ejecución

### Ejecutar el Ejercicio:
```bash
# Verificar dependencias
which jq bc wget tar

# Acceder a la carpeta del ejercicio
cd <nombre-de-la-carpeta>

# Ejecutar
./semana3.sh
```

### Para Re-ejecutar:

> **Nota**: El script se puede ejecutar perfectamente sin necesidad de limpiar previamente. Los cálculos se realizarán en base a los datos existentes actualmente. El script soporta tanto el escenario de una base de datos vacía como una con datos preexistentes.

```bash
# Para testing iterativo (recomendado):
./clean_bitcoin.sh -y && ./semana3.sh  # Limpiar solo datos + ejecutar (RÁPIDO)
./semana3.sh                           # Ejecutar sin limpiar

# Para empezar desde cero:
./clean_bitcoin.sh -y -f && ./semana3.sh  # Limpieza completa + ejecutar
```

### Script de Limpieza:
```bash
# Menú interactivo para elegir tipo de limpieza
./clean_bitcoin.sh

# Ver opciones de limpieza disponibles
./clean_bitcoin.sh --help
```

## Flujo del Ejercicio

1. **Crear billeteras "Miner", "Alice" y "Bob"**
2. **Fondear billetera Miner con 100+ BTC**
3. **Fondear Alice y Bob con 15 BTC cada una**
4. **Obtener claves públicas de Alice y Bob**
5. **Crear dirección multisig 2-de-2**
6. **Enviar fondos al multisig (5 BTC de Alice + 5 BTC de Bob)**
7. **Crear PSBT para gastar fondos multisig**
8. **Demostrar limitaciones de firma en wallets descriptor**
9. **Rastrear UTXOs usando scantxoutset**

## Resultados de Aprendizaje

Al completar este ejercicio entenderás:
- Cómo funcionan las direcciones multisig 2-de-2
- Cómo crear y procesar PSBT (Partially Signed Bitcoin Transactions)  
- Las diferencias entre wallets legacy y descriptor en Bitcoin Core v29
- Cómo rastrear UTXOs externos usando scantxoutset
- Las limitaciones actuales para firma multisig en wallets descriptor

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
- Implementa compatibilidad con wallets descriptor modernas

---