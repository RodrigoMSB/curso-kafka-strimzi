#!/usr/bin/env bash
# Elimina por completo el clúster kind 'meridiano'. Operación DESTRUCTIVA.
# Pide confirmación interactiva, salvo que se pase el flag --si (no interactivo).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

# LAB01_CLUSTER permite apuntar a otro clúster (pruebas 90/91/95). Sin la
# variable, se elimina 'meridiano' como para el alumno.
NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"

# --si omite la confirmación (uso no interactivo, por ejemplo desde el e2e 91).
CONFIRMACION_OMITIDA=0
if [ "${1:-}" = "--si" ]; then
  CONFIRMACION_OMITIDA=1
fi

msg_info "Esta acción ELIMINA por completo el clúster kind '${NOMBRE_CLUSTER}'."
msg_info "Es una operación DESTRUCTIVA: se pierden todos sus recursos."
msg_info "El Lab 02 parte de un clúster limpio, que puedes recrear en minutos"
msg_info "con bin/01-crear-cluster.sh."
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
