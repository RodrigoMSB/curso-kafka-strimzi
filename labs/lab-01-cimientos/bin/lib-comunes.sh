#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 01 de Banco Meridiano.
# No se ejecuta directamente: se carga desde otros scripts con
#   . "$(dirname "$0")/lib-comunes.sh"

# Nota: NO exportar MSYS_NO_PATHCONV. Rompe kind/helm/kubectl en Git Bash.
# El bug de rutas de MSYS2 se resuelve envolviendo los comandos en: bash -c '...'

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
