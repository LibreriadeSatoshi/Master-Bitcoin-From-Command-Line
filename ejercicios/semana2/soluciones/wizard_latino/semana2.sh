#!/bin/bash

# =============================================================================
# SEMANA 2 - Bitcoin Core: Demostración Replace-By-Fee (RBF)
# =============================================================================
# Ejercicio del taller "Master Bitcoin From Command Line"
# Librería de Satoshi
# Autor: wizard_latino
#
# Enlace al ejercicio: https://github.com/LibreriadeSatoshi/Master-Bitcoin-From-Command-Line/blob/main/ejercicios/semana2/ejercicio.md
#
# DESCRIPCIÓN:
# Este ejercicio demuestra el mecanismo Replace-By-Fee (RBF) y su impacto 
# en transacciones child usando una arquitectura modular educativa.
# 
# OBJETIVOS DEL EJERCICIO:
# 1. Demostrar flujos de trabajo de billeteras Bitcoin usando bitcoin-cli
# 2. Ilustrar el mecanismo Replace-By-Fee (RBF)
# 3. Mostrar cómo RBF impacta las transacciones child
#
# PASOS ESPECÍFICOS:
# 1. Crear billeteras "Miner" y "Trader"
# 2. Fondear billetera Miner con 150 BTC
# 3. Crear transacción "Parent" con RBF habilitado
# 4. Transmitir Parent sin minar y analizar mempool
# 5. Crear transacción "Child" gastando output de cambio
# 6. Ejecutar RBF incrementando fee en 10,000 satoshis
# 7. Comparar entradas de mempool antes y después de RBF
# 8. Explicar cambios en estado de child transaction
# 
# MÓDULOS UTILIZADOS:
# - setup_bitcoin.sh: Configuración y descarga de Bitcoin Core
# - manage_wallets.sh: Gestión de billeteras y fondeo
# - rbf_demo.sh: Demostración del mecanismo RBF
#
# ENTORNO DE EJECUCIÓN:
# - Sistema: Linux/Ubuntu (contenedor Docker recomendado)
# - Dependencias: bitcoin-core, jq, bc, wget, gnupg

# Colores para la salida en consola
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color (reset)

# Variables globales
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Función para imprimir líneas separadoras
print_separator() {
    echo -e "${CYAN}========================================${NC}"
}


# Función para mostrar ayuda
show_help() {
    echo -e "${CYAN}Uso: $0 [opciones]${NC}"
    echo -e "${YELLOW}Opciones:${NC}"
    echo -e "  --clean        Limpiar entorno Bitcoin antes de ejecutar"
    echo -e "  --clean-only   Solo limpiar entorno (no ejecutar ejercicio)"
    echo -e "  -h, --help     Mostrar esta ayuda"
    echo ""
    echo -e "${YELLOW}Ejemplos:${NC}"
    echo -e "  $0              # Ejecutar ejercicio normal"
    echo -e "  $0 --clean      # Limpiar y ejecutar ejercicio"
    echo -e "  $0 --clean-only # Solo limpiar entorno"
}

# Función principal
main() {
    local clean_before=false
    local clean_only=false
    
    # Procesar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --clean)
                clean_before=true
                shift
                ;;
            --clean-only)
                clean_only=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Opción desconocida: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_separator
    echo -e "${CYAN}=== SEMANA 2: Replace-By-Fee (RBF) Demonstration ===${NC}"
    echo -e "${YELLOW}Taller: Master Bitcoin From Command Line${NC}"
    echo -e "${YELLOW}Librería de Satoshi${NC}"
    print_separator
    
    # Cargar módulos
    echo -e "${YELLOW}Cargando módulos...${NC}"
    source "${SCRIPT_DIR}/setup_bitcoin.sh"
    source "${SCRIPT_DIR}/manage_wallets.sh"
    source "${SCRIPT_DIR}/rbf_demo.sh"
    source "${SCRIPT_DIR}/clean_bitcoin.sh"
    echo -e "${GREEN}✓ Módulos cargados correctamente${NC}"
    
    # Ejecutar limpieza si se solicita
    if [ "$clean_before" = true ] || [ "$clean_only" = true ]; then
        print_separator
        echo -e "${CYAN}LIMPIEZA DE ENTORNO SOLICITADA${NC}"
        print_separator
        clean_bitcoin_environment true false true  # auto_confirm=true, verbose=false, full_clean=true
        
        if [ "$clean_only" = true ]; then
            echo -e "${GREEN}✓ Limpieza completada. Saliendo...${NC}"
            exit 0
        fi
    fi
    
    print_separator
    echo -e "${CYAN}FASE 1: CONFIGURACIÓN DEL ENTORNO${NC}"
    print_separator
    
    # Configurar Bitcoin Core
    setup_bitcoin_core
    
    print_separator
    echo -e "${CYAN}FASE 2: PREPARACIÓN DE BILLETERAS${NC}"
    print_separator
    
    # Configurar billeteras
    setup_wallet_environment
    
    print_separator
    echo -e "${CYAN}FASE 3: DEMOSTRACIÓN RBF vs CPFP${NC}"
    print_separator
    
    # Ejecutar demostración
    demonstrate_rbf_vs_cpfp
    
    print_separator
    echo -e "${CYAN}=== EJERCICIO SEMANA 2 COMPLETADO ===${NC}"
    echo -e "${CYAN}Arquitectura modular utilizada:${NC}"
    echo -e "  • setup_bitcoin.sh - Configuración base"
    echo -e "  • manage_wallets.sh - Gestión de billeteras"
    echo -e "  • rbf_demo.sh - Demostración RBF"
    echo -e "  • clean_bitcoin.sh - Limpieza de entorno"
    echo -e "${YELLOW}Todos los módulos son reutilizables dentro de esta carpeta${NC}"
    
    print_separator
    echo -e "${CYAN}OPCIONES PARA VOLVER A EJECUTAR:${NC}"
    echo -e "${YELLOW}Para testing iterativo (recomendado):${NC}"
    echo -e "  • ./clean_bitcoin.sh -y && ./semana2.sh  # Limpiar solo datos + ejecutar (RÁPIDO)"
    echo -e "  • ./semana2.sh                           # Ejecutar sin limpiar"
    echo -e "${YELLOW}Para empezar desde cero:${NC}"
    echo -e "  • ./clean_bitcoin.sh -y -f && ./semana2.sh  # Limpieza completa + ejecutar"
    echo -e "  • ./semana2.sh --clean                      # Limpieza completa + ejecutar"
    echo -e "${YELLOW}Opciones de limpieza:${NC}"
    echo -e "  • ./clean_bitcoin.sh --help                 # Ver todas las opciones"
    print_separator
}

# Ejecutar script principal
main "$@"