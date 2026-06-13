#!/usr/bin/env bash
# Verifica los prerrequisitos del Capstone: estado final del Lab 07 en verde (la
# plataforma completa: 3 brokers + Cruise Control, DR en 4.2.0, CDC, observabilidad).
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
LAB07_90="$DIR_SCRIPT/../../lab-07-operacion/bin/90-test-lab.sh"
errores=0

msg_info "Verificando prerrequisitos del Capstone 'La migración'..."
echo
if [ -f "$LAB07_90" ] && bash "$LAB07_90" >/tmp/capstone-lab07-90.out 2>&1; then
  msg_ok "Plataforma del Lab 07 en verde (su test 90 pasa)."
else
  msg_error "El Lab 07 no está completo. Recupéralo con: labs/lab-07-operacion/bin/95-recuperar-lab.sh"
  msg_error "Detalle en /tmp/capstone-lab07-90.out"
  errores=$((errores + 1))
fi

if ! verificar_comando docker; then
  msg_error "Falta 'docker' (el Kafka legado corre como contenedor en la red de kind)."
  errores=$((errores + 1))
fi

uso_mib=$(memoria_docker_mib)
msg_info "Memoria del Docker VM en uso por contenedores: ~${uso_mib:-?} MiB. El legado + MM2 añaden carga."

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Capstone."
else
  msg_error "Prerrequisitos NO satisfechos (${errores})."
  exit 1
fi
