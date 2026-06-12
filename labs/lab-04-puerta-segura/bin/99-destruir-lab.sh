#!/usr/bin/env bash
# Destruye por completo el clúster kind del curso (el mismo de todos los labs).
# Operación DESTRUCTIVA. Interactivo salvo --si.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"

CONFIRMACION_OMITIDA=0
[ "${1:-}" = "--si" ] && CONFIRMACION_OMITIDA=1

msg_info "Esta acción ELIMINA por completo el clúster kind '${NOMBRE_CLUSTER}'."
msg_info "Es el único clúster del curso: se pierden los labs 01 a 04."
msg_info "Puedes reconstruir el estado del Lab 04 con bin/95-recuperar-lab.sh."
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
  # Higiene: las credenciales extraídas mueren con el clúster que las emitió.
  DIR_CRED="$DIR_SCRIPT/../credenciales"
  if [ -d "$DIR_CRED" ]; then
    rm -rf "$DIR_CRED"
    msg_info "Eliminadas las credenciales locales de ./credenciales/ (ya no sirven: los certificados murieron con el clúster)."
  fi
else
  msg_info "Operación cancelada. No se eliminó nada."
fi
