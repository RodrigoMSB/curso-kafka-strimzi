#!/usr/bin/env bash
# Crea el clúster kind 'meridiano' a partir de infra/kind-config.yaml.
# Es idempotente: si el clúster ya existe, lo informa y termina sin error.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="meridiano"
ARCHIVO_CONFIG="$DIR_SCRIPT/../infra/kind-config.yaml"

if [ ! -f "$ARCHIVO_CONFIG" ]; then
  msg_error "No se encontró el archivo de configuración: $ARCHIVO_CONFIG"
  exit 1
fi

# Idempotencia: si ya existe un clúster con ese nombre, no se recrea.
if kind get clusters 2>/dev/null | grep -q "^${NOMBRE_CLUSTER}$"; then
  msg_info "El clúster kind '${NOMBRE_CLUSTER}' ya existe. No se crea de nuevo."
else
  msg_info "Creando el clúster kind '${NOMBRE_CLUSTER}' (la primera vez puede tardar al descargar la imagen del nodo)..."
  kind create cluster --name "$NOMBRE_CLUSTER" --config "$ARCHIVO_CONFIG"
  msg_ok "Clúster '${NOMBRE_CLUSTER}' creado."
fi

echo
msg_info "Nodos del clúster:"
kubectl get nodes --context "kind-${NOMBRE_CLUSTER}"
msg_info "Si el nodo aparece NotReady los primeros segundos es normal: la red interna está arrancando. Espera un momento y vuelve a consultar."
