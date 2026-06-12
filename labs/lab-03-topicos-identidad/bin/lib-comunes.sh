#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 03 de Banco Meridiano.
# Se carga desde otros scripts con:  . "$(dirname "$0")/lib-comunes.sh"

msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }

verificar_comando() {
  if command -v "$1" >/dev/null 2>&1; then return 0; else return 1; fi
}
