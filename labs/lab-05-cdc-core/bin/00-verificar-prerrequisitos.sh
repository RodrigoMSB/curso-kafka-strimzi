#!/usr/bin/env bash
# Verifica los prerrequisitos del Lab 05:
#   1) Estado final del Lab 04 (su test 90 en verde).
#   2) Registry local operativo (o instrucción de crearlo).
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

LAB04_90="$DIR_SCRIPT/../../lab-04-puerta-segura/bin/90-test-lab.sh"
errores=0

msg_info "Verificando prerrequisitos del Lab 05..."
echo

if [ -f "$LAB04_90" ] && bash "$LAB04_90" >/tmp/lab05-lab04-90.out 2>&1; then
  msg_ok "Estado final del Lab 04 presente (su test 90 en verde)."
else
  msg_error "El Lab 04 no está completo. Recupéralo con: labs/lab-04-puerta-segura/bin/95-recuperar-lab.sh"
  errores=$((errores + 1))
fi

if [ -n "$(docker ps -q -f name='^kind-registry$')" ]; then
  msg_ok "Registry local 'kind-registry' operativo."
else
  msg_error "El registry local no está corriendo. Créalo con: bin/01-registry-local.sh"
  errores=$((errores + 1))
fi

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Lab 05."
else
  msg_error "Prerrequisitos NO satisfechos (${errores})."
  exit 1
fi
