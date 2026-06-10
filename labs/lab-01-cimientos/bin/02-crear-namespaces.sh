#!/usr/bin/env bash
# Crea los namespaces 'meridiano-sistema' y 'meridiano-pagos'.
# Tolerante a existencia previa (patrón create --dry-run | apply).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CONTEXTO="kind-meridiano"

for ns in meridiano-sistema meridiano-pagos; do
  msg_info "Asegurando el namespace '${ns}'..."
  kubectl create namespace "$ns" --context "$CONTEXTO" --dry-run=client -o yaml \
    | kubectl apply --context "$CONTEXTO" -f -
done

echo
msg_ok "Namespaces listos."
msg_info "Verifica con: kubectl get namespaces | grep meridiano"
