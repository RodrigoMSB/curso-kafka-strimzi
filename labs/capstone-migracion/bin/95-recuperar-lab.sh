#!/usr/bin/env bash
# Recuperación del Capstone: reconstruye el ESTADO FINAL (migración completada)
# sin pasar por el escenario. Encadena el 95 del Lab 07 (plataforma completa) y
# luego ejecuta la SOLUCIÓN de referencia de la migración. Hereda el exit code
# del test 90 del capstone.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
SOL="$DIR_SCRIPT/../soluciones"
LAB07_95="$DIR_SCRIPT/../../lab-07-operacion/bin/95-recuperar-lab.sh"

msg_info "Este script reconstruye el resultado del Capstone sin pasar por el escenario."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en diseñar y ejecutar la migración."
echo

# 1. Estado final del Lab 07 (la plataforma completa: la cadena entera del curso).
msg_info "Reconstruyendo primero la plataforma del Lab 07 (cadena completa del curso)..."
if ! bash "$LAB07_95" >/tmp/capstone-lab07-95.out 2>&1; then
  msg_error "La recuperación del Lab 07 falló. Detalle:"; tail -n 15 /tmp/capstone-lab07-95.out | sed 's/^/    /'; exit 1
fi
msg_ok "Plataforma del Lab 07 reconstruida."

# 2. Ejecutar la solución de referencia de la migración de punta a punta.
echo
ejecutar_migracion "$CONTEXTO" "$NSP" "$SOL" "$DIR_SCRIPT"

# 3. Verificación final.
echo
msg_info "Ejecutando el evaluador del capstone (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
