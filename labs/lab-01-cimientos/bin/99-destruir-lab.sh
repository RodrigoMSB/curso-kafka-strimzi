#!/usr/bin/env bash
# Elimina por completo el clúster kind 'meridiano'. Operación DESTRUCTIVA.
# Pide confirmación interactiva antes de actuar.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="meridiano"

msg_info "Esta acción ELIMINA por completo el clúster kind '${NOMBRE_CLUSTER}'."
msg_info "Es una operación DESTRUCTIVA: se pierden todos sus recursos."
msg_info "El Lab 02 parte de un clúster limpio, que puedes recrear en minutos"
msg_info "con bin/01-crear-cluster.sh."
echo
printf '¿Confirmas la eliminación? Escribe "si" para continuar: '
read -r respuesta

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
