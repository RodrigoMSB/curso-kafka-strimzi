#!/usr/bin/env bash
# Destruye por completo el clúster kind del curso. Es el MISMO clúster de todos
# los labs (uno solo que evoluciona), así que esto borra también el trabajo del
# Lab 01. Operación DESTRUCTIVA.
# Pide confirmación interactiva, salvo que se pase el flag --si.
#
# LAB01_CLUSTER permite apuntar a otro clúster (lo usa el e2e 91).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"

CONFIRMACION_OMITIDA=0
if [ "${1:-}" = "--si" ]; then
  CONFIRMACION_OMITIDA=1
fi

msg_info "Esta acción ELIMINA por completo el clúster kind '${NOMBRE_CLUSTER}'."
msg_info "Es el único clúster del curso: se pierden el Lab 01 y el Lab 02."
msg_info "Puedes reconstruir el estado del Lab 02 con bin/95-recuperar-lab.sh."
echo

if [ "$CONFIRMACION_OMITIDA" -eq 1 ]; then
  msg_info "Confirmación omitida por el flag --si (modo no interactivo)."
  respuesta="si"
else
  printf '¿Confirmas la eliminación? Escribe "si" para continuar: '
  read -r respuesta
fi

if [ "$respuesta" = "si" ]; then
  if kind get clusters 2>/dev/null | grep -q "^${NOMBRE_CLUSTER}$"; then
    kind delete cluster --name "$NOMBRE_CLUSTER"
    msg_ok "Clúster '${NOMBRE_CLUSTER}' eliminado."
  else
    msg_info "El clúster '${NOMBRE_CLUSTER}' no existe. Nada que eliminar."
  fi
else
  msg_info "Operación cancelada. No se eliminó nada."
fi
