#!/usr/bin/env bash
# Verifica los prerrequisitos del Lab 06:
#   1) Estado final del Lab 05 (su test 90 en verde).
#   2) Advertencia de memoria: este lab agrega un 2º clúster Kafka, MM2,
#      Prometheus y Grafana. Es el más pesado del curso.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
LAB05_90="$DIR_SCRIPT/../../lab-05-cdc-core/bin/90-test-lab.sh"
errores=0

msg_info "Verificando prerrequisitos del Lab 06..."
echo

if [ -f "$LAB05_90" ] && bash "$LAB05_90" >/tmp/lab06-lab05-90.out 2>&1; then
  msg_ok "Estado final del Lab 05 presente (su test 90 en verde)."
else
  msg_error "El Lab 05 no está completo. Recupéralo con: labs/lab-05-cdc-core/bin/95-recuperar-lab.sh"
  errores=$((errores + 1))
fi

# Advertencia de memoria (no bloqueante).
total_mib=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1048576}')
uso_mib=$(memoria_docker_mib)
msg_info "Memoria del Docker VM: total ~${total_mib:-?} MiB, en uso por contenedores ~${uso_mib:-?} MiB."
if [ -n "$total_mib" ] && [ "$total_mib" -lt 14000 ] 2>/dev/null; then
  msg_info "ADVERTENCIA: este lab va justo en 16 GB. Cierra aplicaciones pesadas (navegadores, IDEs) antes de continuar."
fi

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Lab 06 (vigila la memoria)."
else
  msg_error "Prerrequisitos NO satisfechos (${errores})."
  exit 1
fi
