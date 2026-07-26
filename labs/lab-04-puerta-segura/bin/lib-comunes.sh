#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 04 de Banco Meridiano.

# Nota: NO exportar MSYS_NO_PATHCONV. Rompe kind/helm/kubectl en Git Bash.
# El bug de rutas de MSYS2 se resuelve envolviendo los comandos en: bash -c '...'

msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }
verificar_comando() { if command -v "$1" >/dev/null 2>&1; then return 0; else return 1; fi; }
