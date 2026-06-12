#!/usr/bin/env bash
# Destruye el clúster kind del curso Y el contenedor del registry local.
# El namespace meridiano-core muere con el clúster. Operación DESTRUCTIVA.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"

CONFIRMACION_OMITIDA=0
[ "${1:-}" = "--si" ] && CONFIRMACION_OMITIDA=1

msg_info "Esta acción ELIMINA el clúster kind '${NOMBRE_CLUSTER}', el namespace"
msg_info "meridiano-core (el core PostgreSQL) y el contenedor del registry local."
msg_info "Reconstruye el estado del Lab 05 con bin/95-recuperar-lab.sh."
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
    msg_ok "Clúster '${NOMBRE_CLUSTER}' eliminado (con él, el core PostgreSQL)."
  else
    msg_info "El clúster '${NOMBRE_CLUSTER}' no existe."
  fi
  if [ -n "$(docker ps -aq -f name='^kind-registry$')" ]; then
    docker rm -f kind-registry >/dev/null 2>&1 || true
    msg_ok "Contenedor del registry local eliminado."
  fi
else
  msg_info "Operación cancelada. No se eliminó nada."
fi
