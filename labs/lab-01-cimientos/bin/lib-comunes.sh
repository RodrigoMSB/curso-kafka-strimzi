#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 01 de Banco Meridiano.
# No se ejecuta directamente: se carga desde otros scripts con
#   . "$(dirname "$0")/lib-comunes.sh"

# Git Bash (MSYS2) reescribe los argumentos que parecen rutas Unix a rutas Windows
# antes de pasarlos al comando. Eso rompe cualquier '--command-config /props/...' que
# viaje como argumento directo de 'kubectl exec'. Desactivarlo es inocuo en macOS y
# Linux (la variable simplemente no se usa).
export MSYS_NO_PATHCONV=1

# --- Impresión con prefijos en español neutro ---
msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }

# Verifica que un comando esté disponible en el PATH.
# Uso:  verificar_comando kubectl  ->  devuelve 0 si existe, 1 si no.
verificar_comando() {
  comando_a_buscar="$1"
  if command -v "$comando_a_buscar" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}
