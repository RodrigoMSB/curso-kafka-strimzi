#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 02 de Banco Meridiano.
# Se carga desde otros scripts con:  . "$(dirname "$0")/lib-comunes.sh"

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
verificar_comando() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}
