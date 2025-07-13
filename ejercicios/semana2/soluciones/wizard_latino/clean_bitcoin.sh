#!/bin/bash

# =============================================================================
# MÓDULO: Limpieza de Entorno Bitcoin
# =============================================================================
# Taller: Master Bitcoin From Command Line
# Librería de Satoshi
# Autor: wizard_latino
#
# Descripción: Módulo para limpiar completamente el entorno Bitcoin
# - Detiene bitcoind si está corriendo
# - Elimina binarios de Bitcoin Core
# - Elimina archivos de descarga y configuración
# - Permite testing desde cero de scripts modulares
# Uso: ./clean_bitcoin.sh o source clean_bitcoin.sh

# Colores para la salida
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Variables de directorios
BITCOIN_TOOLS_DIR="${HOME}/bitcoin-tools"
BITCOIN_BIN_DIR="${BITCOIN_TOOLS_DIR}/bin"
BITCOIN_DOWNLOADS_DIR="${BITCOIN_TOOLS_DIR}/downloads"
BITCOIN_CONFIG="${HOME}/.bitcoin"

# Función para imprimir separadores
print_separator() {
    echo -e "${CYAN}========================================${NC}"
}

# Función para mostrar información de uso
show_usage() {
    echo -e "${CYAN}Uso: $0 [opciones]${NC}"
    echo -e "${YELLOW}Opciones:${NC}"
    echo -e "  -y, --yes         Eliminar sin confirmación (requiere -f para completa)"
    echo -e "  -v, --verbose     Mostrar detalles de archivos eliminados"
    echo -e "  -f, --full        Limpieza completa (incluye binarios)"
    echo -e "  -h, --help        Mostrar esta ayuda"
    echo ""
    echo -e "${YELLOW}Comportamiento por defecto (sin argumentos):${NC}"
    echo -e "  • Muestra menú interactivo para elegir tipo de limpieza"
    echo -e "  • Opción 1: Solo datos (mantiene binarios - RÁPIDO)"
    echo -e "  • Opción 2: Limpieza completa (elimina todo)"
    echo -e "  • Opción 3: Cancelar"
    echo ""
    echo -e "${YELLOW}Ejemplos:${NC}"
    echo -e "  $0                # Menú interactivo (RECOMENDADO)"
    echo -e "  $0 -v             # Menú interactivo con detalles"
    echo -e "  $0 -y             # Solo datos automático (mantiene binarios)"
    echo -e "  $0 -y -f          # Limpieza completa automática"
    echo -e "  $0 -f             # Limpieza completa con confirmación"
    echo -e "  $0 -y -v          # Solo datos automático con detalles"
    echo -e "  $0 -y -f -v       # Limpieza completa automática con detalles"
}

# Función para obtener tamaño de directorio
get_dir_size() {
    local dir="$1"
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

# Función para mostrar estado actual
show_current_state() {
    local full_clean=${1:-false}
    
    print_separator
    echo -e "${CYAN}ESTADO ACTUAL DEL SISTEMA BITCOIN${NC}"
    print_separator
    
    echo -e "${YELLOW}Verificando procesos Bitcoin...${NC}"
    if pgrep bitcoind > /dev/null; then
        echo -e "${RED}✗ bitcoind está corriendo${NC}"
    else
        echo -e "${GREEN}✓ bitcoind no está corriendo${NC}"
    fi
    
    echo -e "${YELLOW}Verificando directorios...${NC}"
    
    if [ "$full_clean" = true ]; then
        if [ -d "$BITCOIN_BIN_DIR" ]; then
            local size=$(get_dir_size "$BITCOIN_BIN_DIR")
            echo -e "${RED}✗ Binarios Bitcoin: $BITCOIN_BIN_DIR ($size)${NC}"
        else
            echo -e "${GREEN}✓ No hay binarios Bitcoin${NC}"
        fi
        
        if [ -d "$BITCOIN_DOWNLOADS_DIR" ]; then
            local size=$(get_dir_size "$BITCOIN_DOWNLOADS_DIR")
            echo -e "${RED}✗ Archivos descarga: $BITCOIN_DOWNLOADS_DIR ($size)${NC}"
        else
            echo -e "${GREEN}✓ No hay archivos de descarga${NC}"
        fi
    else
        if [ -d "$BITCOIN_BIN_DIR" ]; then
            local size=$(get_dir_size "$BITCOIN_BIN_DIR")
            echo -e "${CYAN}→ Binarios Bitcoin: $BITCOIN_BIN_DIR ($size) [SE MANTENDRÁN]${NC}"
        fi
        
        if [ -d "$BITCOIN_DOWNLOADS_DIR" ]; then
            local size=$(get_dir_size "$BITCOIN_DOWNLOADS_DIR")
            echo -e "${CYAN}→ Archivos descarga: $BITCOIN_DOWNLOADS_DIR ($size) [SE MANTENDRÁN]${NC}"
        fi
    fi
    
    if [ -d "$BITCOIN_CONFIG" ]; then
        local size=$(get_dir_size "$BITCOIN_CONFIG")
        echo -e "${RED}✗ Configuración Bitcoin: $BITCOIN_CONFIG ($size)${NC}"
    else
        echo -e "${GREEN}✓ No hay configuración Bitcoin${NC}"
    fi
}

# Función para detener bitcoind
stop_bitcoind() {
    echo -e "${YELLOW}Deteniendo bitcoind si está corriendo...${NC}"
    
    if pgrep bitcoind > /dev/null; then
        # Intentar parada limpia primero
        if [ -f "$BITCOIN_BIN_DIR/bitcoin-cli" ]; then
            "$BITCOIN_BIN_DIR/bitcoin-cli" -regtest stop 2>/dev/null || true
            sleep 3
        fi
        
        # Si aún está corriendo, usar kill
        if pgrep bitcoind > /dev/null; then
            echo -e "${YELLOW}Forzando cierre de bitcoind...${NC}"
            pkill bitcoind 2>/dev/null || true
            sleep 2
        fi
        
        # Verificación final
        if pgrep bitcoind > /dev/null; then
            echo -e "${RED}⚠ bitcoind aún corriendo. Puede requerir kill manual.${NC}"
        else
            echo -e "${GREEN}✓ bitcoind detenido correctamente${NC}"
        fi
    else
        echo -e "${GREEN}✓ bitcoind no estaba corriendo${NC}"
    fi
}

# Función para eliminar directorio con detalles
remove_directory() {
    local dir="$1"
    local name="$2"
    local verbose="$3"
    
    if [ -d "$dir" ]; then
        local size=$(get_dir_size "$dir")
        echo -e "${YELLOW}Eliminando $name ($size)...${NC}"
        
        if [ "$verbose" = "true" ]; then
            echo -e "${CYAN}Archivos en $dir:${NC}"
            find "$dir" -type f -exec basename {} \; 2>/dev/null | head -10
            local count=$(find "$dir" -type f 2>/dev/null | wc -l)
            if [ "$count" -gt 10 ]; then
                echo -e "${CYAN}... y $((count - 10)) archivos más${NC}"
            fi
        fi
        
        rm -rf "$dir"
        
        if [ ! -d "$dir" ]; then
            echo -e "${GREEN}✓ $name eliminado ($size liberados)${NC}"
        else
            echo -e "${RED}✗ Error eliminando $name${NC}"
        fi
    else
        echo -e "${GREEN}✓ $name no existe${NC}"
    fi
}

# Función principal de limpieza
perform_cleanup() {
    local verbose="$1"
    local full_clean="$2"
    
    print_separator
    if [ "$full_clean" = true ]; then
        echo -e "${CYAN}INICIANDO LIMPIEZA COMPLETA${NC}"
        echo -e "${YELLOW}Limpiando todo (binarios, datos y configuración)${NC}"
    else
        echo -e "${CYAN}INICIANDO LIMPIEZA DE DATOS${NC}"
        echo -e "${YELLOW}Limpiando solo datos (manteniendo binarios para ejecución rápida)${NC}"
    fi
    print_separator
    
    # Detener bitcoind
    stop_bitcoind
    
    # Eliminar directorios según modo
    if [ "$full_clean" = true ]; then
        remove_directory "$BITCOIN_BIN_DIR" "Binarios Bitcoin" "$verbose"
        remove_directory "$BITCOIN_DOWNLOADS_DIR" "Archivos de descarga" "$verbose"
    else
        echo -e "${CYAN}→ Manteniendo binarios en: $BITCOIN_BIN_DIR${NC}"
        echo -e "${CYAN}→ Manteniendo descargas en: $BITCOIN_DOWNLOADS_DIR${NC}"
    fi
    
    remove_directory "$BITCOIN_CONFIG" "Configuración Bitcoin" "$verbose"
    
    print_separator
    echo -e "${GREEN}LIMPIEZA COMPLETADA${NC}"
    if [ "$full_clean" = true ]; then
        echo -e "${CYAN}Los scripts de esta carpeta descargarán Bitcoin Core automáticamente${NC}"
    else
        echo -e "${CYAN}Binarios mantenidos - El próximo ejercicio será más rápido${NC}"
    fi
    print_separator
}

# Función para verificar limpieza
verify_cleanup() {
    local full_clean="$1"
    
    echo -e "${YELLOW}Verificando limpieza...${NC}"
    
    local all_clean=true
    
    # Verificar procesos
    if pgrep bitcoind > /dev/null; then
        echo -e "${RED}✗ bitcoind aún corriendo${NC}"
        all_clean=false
    fi
    
    # Verificar directorios según modo
    if [ "$full_clean" = true ]; then
        for dir in "$BITCOIN_BIN_DIR" "$BITCOIN_DOWNLOADS_DIR" "$BITCOIN_CONFIG"; do
            if [ -d "$dir" ]; then
                echo -e "${RED}✗ Directorio aún existe: $dir${NC}"
                all_clean=false
            fi
        done
    else
        # Solo verificar configuración en modo data-only
        if [ -d "$BITCOIN_CONFIG" ]; then
            echo -e "${RED}✗ Directorio aún existe: $BITCOIN_CONFIG${NC}"
            all_clean=false
        fi
    fi
    
    if [ "$all_clean" = "true" ]; then
        if [ "$full_clean" = true ]; then
            echo -e "${GREEN}✓ Sistema completamente limpio${NC}"
            echo -e "${CYAN}Listo para ejecutar ejercicios de esta carpeta desde cero${NC}"
        else
            echo -e "${GREEN}✓ Datos limpiados (binarios mantenidos)${NC}"
            echo -e "${CYAN}Listo para ejecutar ejercicio rápidamente${NC}"
        fi
        return 0
    else
        echo -e "${RED}⚠ Limpieza incompleta${NC}"
        return 1
    fi
}

# Función principal para uso como módulo
clean_bitcoin_environment() {
    local auto_confirm=${1:-false}
    local verbose=${2:-false}
    local full_clean=${3:-false}
    
    echo -e "${CYAN}=== MÓDULO DE LIMPIEZA BITCOIN ===${NC}"
    show_current_state "$full_clean"
    
    # Verificar si hay algo que limpiar
    if [ "$full_clean" = true ]; then
        if [ ! -d "$BITCOIN_BIN_DIR" ] && [ ! -d "$BITCOIN_DOWNLOADS_DIR" ] && [ ! -d "$BITCOIN_CONFIG" ] && ! pgrep bitcoind > /dev/null; then
            echo -e "${GREEN}✓ El sistema ya está limpio${NC}"
            return 0
        fi
    else
        if [ ! -d "$BITCOIN_CONFIG" ] && ! pgrep bitcoind > /dev/null; then
            echo -e "${GREEN}✓ Los datos ya están limpios${NC}"
            return 0
        fi
    fi
    
    if [ "$auto_confirm" = false ]; then
        print_separator
        if [ "$full_clean" = true ]; then
            echo -e "${YELLOW}¿Continuar con limpieza COMPLETA? Esto eliminará:${NC}"
            [ -d "$BITCOIN_BIN_DIR" ] && echo -e "  • Binarios Bitcoin ($(get_dir_size "$BITCOIN_BIN_DIR"))"
            [ -d "$BITCOIN_DOWNLOADS_DIR" ] && echo -e "  • Archivos descarga ($(get_dir_size "$BITCOIN_DOWNLOADS_DIR"))"
            [ -d "$BITCOIN_CONFIG" ] && echo -e "  • Configuración/datos ($(get_dir_size "$BITCOIN_CONFIG"))"
        else
            echo -e "${YELLOW}¿Continuar con limpieza de DATOS? Esto eliminará:${NC}"
            [ -d "$BITCOIN_CONFIG" ] && echo -e "  • Configuración/datos ($(get_dir_size "$BITCOIN_CONFIG"))"
            echo -e "${CYAN}  → Binarios se mantendrán para ejecución rápida${NC}"
        fi
        echo ""
        read -p "Escriba 'si' para confirmar: " response
        
        if [ "$response" != "si" ]; then
            echo -e "${YELLOW}Limpieza cancelada${NC}"
            return 0
        fi
    fi
    
    perform_cleanup "$verbose" "$full_clean"
    verify_cleanup "$full_clean"
}

# Función para mostrar menú interactivo
show_interactive_menu() {
    local verbose="$1"
    
    print_separator
    echo -e "${CYAN}=== MENÚ DE LIMPIEZA BITCOIN ===${NC}"
    show_current_state false  # Mostrar estado con datos por defecto
    
    print_separator
    echo -e "${CYAN}OPCIONES DE LIMPIEZA DISPONIBLES:${NC}"
    echo ""
    echo -e "${GREEN}[1] Limpieza de DATOS (RECOMENDADA)${NC}"
    echo -e "    • Elimina: Configuración y blockchain regtest"
    echo -e "    • Mantiene: Binarios y archivos de descarga"
    echo -e "    • Tiempo: ~2-3 segundos"
    echo -e "    • Ideal para: Testing iterativo rápido"
    echo ""
    echo -e "${YELLOW}[2] Limpieza COMPLETA${NC}"
    echo -e "    • Elimina: TODO (binarios, descargas, configuración)"
    echo -e "    • Tiempo: ~5-10 segundos"
    echo -e "    • Ideal para: Empezar completamente desde cero"
    echo ""
    echo -e "${CYAN}[3] Cancelar${NC}"
    echo ""
    
    while true; do
        read -p "Selecciona una opción [1-3]: " choice
        case $choice in
            1)
                echo -e "${GREEN}✓ Seleccionaste: Limpieza de DATOS${NC}"
                clean_bitcoin_environment false "$verbose" false
                break
                ;;
            2)
                echo -e "${YELLOW}✓ Seleccionaste: Limpieza COMPLETA${NC}"
                clean_bitcoin_environment false "$verbose" true
                break
                ;;
            3)
                echo -e "${CYAN}Limpieza cancelada por el usuario${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opción inválida. Por favor selecciona 1, 2 o 3.${NC}"
                ;;
        esac
    done
}

# Función principal para uso standalone
main() {
    local auto_confirm=false
    local verbose=false
    local full_clean=false
    local interactive_mode=true
    
    # Procesar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            -y|--yes)
                auto_confirm=true
                interactive_mode=false
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -f|--full)
                full_clean=true
                interactive_mode=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                echo -e "${RED}Opción desconocida: $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Si no hay argumentos o solo -v, mostrar menú interactivo
    if [ "$interactive_mode" = true ]; then
        show_interactive_menu "$verbose"
    else
        clean_bitcoin_environment "$auto_confirm" "$verbose" "$full_clean"
    fi
}

# Ejecutar solo si se llama directamente (no como módulo)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi