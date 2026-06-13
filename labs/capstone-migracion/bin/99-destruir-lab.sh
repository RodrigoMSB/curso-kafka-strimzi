#!/usr/bin/env bash
# Destruye el clúster kind del curso, el contenedor del Kafka LEGADO y el del
# registry local. Todo (pagos, dr, observabilidad, core, legado) muere. DESTRUCTIVA.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"

CONFIRMACION_OMITIDA=0
[ "${1:-}" = "--si" ] && CONFIRMACION_OMITIDA=1

msg_info "Esta acción ELIMINA el clúster kind '${NOMBRE_CLUSTER}' (pagos, dr,"
msg_info "observabilidad, core), el contenedor del Kafka legado y el registry local."
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
    msg_info "El clúster '${NOMBRE_CLUSTER}' no existe."
  fi
  if [ -n "$(docker ps -aq -f name="^${LEGADO_NOMBRE}$" 2>/dev/null)" ]; then
    docker rm -f "$LEGADO_NOMBRE" >/dev/null 2>&1 || true
    msg_ok "Contenedor del Kafka legado '${LEGADO_NOMBRE}' eliminado."
  fi
  if [ -n "$(docker ps -aq -f name='^kind-registry$' 2>/dev/null)" ]; then
    docker rm -f kind-registry >/dev/null 2>&1 || true
    msg_ok "Contenedor del registry local eliminado."
  fi
else
  msg_info "Operación cancelada. No se eliminó nada."
fi
