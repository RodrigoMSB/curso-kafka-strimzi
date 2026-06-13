#!/usr/bin/env bash
# Verifica los prerrequisitos del Lab 07: estado final del Lab 06 (su test 90).
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
LAB06_90="$DIR_SCRIPT/../../lab-06-contingencia-ojos/bin/90-test-lab.sh"
errores=0

msg_info "Verificando prerrequisitos del Lab 07..."
echo
if [ -f "$LAB06_90" ] && bash "$LAB06_90" >/tmp/lab07-lab06-90.out 2>&1; then
  msg_ok "Estado final del Lab 06 presente (su test 90 en verde)."
else
  msg_error "El Lab 06 no está completo. Recupéralo con: labs/lab-06-contingencia-ojos/bin/95-recuperar-lab.sh"
  errores=$((errores + 1))
fi

uso_mib=$(memoria_docker_mib)
msg_info "Memoria del Docker VM en uso por contenedores: ~${uso_mib:-?} MiB. Cruise Control y un 4º broker temporal añaden carga."

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Lab 07."
else
  msg_error "Prerrequisitos NO satisfechos (${errores})."
  exit 1
fi
