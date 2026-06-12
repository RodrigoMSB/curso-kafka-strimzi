#!/usr/bin/env bash
# Despliega el core legado (PostgreSQL) en el namespace meridiano-core y espera
# a que esté listo con la tabla semilla. Idempotente.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
CORE="$DIR_SCRIPT/../infra/core"

msg_info "Desplegando el core PostgreSQL en meridiano-core..."
kubectl apply --context "$CONTEXTO" -f "$CORE/"

msg_info "Esperando a que PostgreSQL esté disponible (máximo 180s)..."
if kubectl rollout status deployment/core-postgres -n meridiano-core --context "$CONTEXTO" --timeout=180s; then
  msg_ok "PostgreSQL del core desplegado."
else
  msg_error "El core no quedó disponible. Revisa 'kubectl get pods -n meridiano-core'."
  exit 1
fi

# Verificación rápida: la tabla semilla existe.
POD=$(kubectl get pod -n meridiano-core --context "$CONTEXTO" -l app=core-postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ] && kubectl exec -n meridiano-core --context "$CONTEXTO" "$POD" -- \
     psql -U postgres -d meridiano -tAc "SELECT count(*) FROM clientes" >/dev/null 2>&1; then
  msg_ok "Tabla 'clientes' presente con datos semilla."
else
  msg_info "El init de la tabla puede tardar unos segundos más tras el arranque."
fi
