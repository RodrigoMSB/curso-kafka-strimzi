#!/usr/bin/env bash
# Funciones comunes para los scripts del Lab 06 de Banco Meridiano.

# Git Bash (MSYS2) reescribe los argumentos que parecen rutas Unix a rutas Windows
# antes de pasarlos al comando. Eso rompe cualquier '--command-config /props/...' que
# viaje como argumento directo de 'kubectl exec'. Desactivarlo es inocuo en macOS y
# Linux (la variable simplemente no se usa).
export MSYS_NO_PATHCONV=1

msg_ok()    { printf '[OK] %s\n' "$*"; }
msg_info()  { printf '[INFO] %s\n' "$*"; }
msg_error() { printf '[ERROR] %s\n' "$*" >&2; }
verificar_comando() { if command -v "$1" >/dev/null 2>&1; then return 0; else return 1; fi; }

# Memoria del Docker VM en uso por contenedores (suma de MemUsage), en MiB.
# Devuelve "?" si no se puede calcular.
memoria_docker_mib() {
  docker stats --no-stream --format '{{.MemUsage}}' 2>/dev/null \
    | awk '{u=$1; if (u ~ /GiB/){sub(/GiB/,"",u); s+=u*1024} else if (u ~ /MiB/){sub(/MiB/,"",u); s+=u} } END{ if (NR>0) printf "%d", s; else printf "?" }'
}
