#!/usr/bin/env bash
# Etiqueta los 3 workers del clúster con tres zonas de disponibilidad simuladas
# (zona-a/b/c) usando la etiqueta estándar topology.kubernetes.io/zone.
# Idempotente: se puede repetir; sobrescribe la etiqueta sin error.
#
# LAB01_CLUSTER permite apuntar a otro clúster (lo usan 90/91/95).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
ZONAS="zona-a zona-b zona-c"

# Workers = nodos SIN la etiqueta de control-plane, ordenados por nombre.
workers=$(kubectl get nodes --context "$CONTEXTO" \
  -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)

cantidad=$(printf '%s\n' "$workers" | grep -c . || true)
if [ "$cantidad" -ne 3 ]; then
  msg_error "Se esperaban 3 workers y se encontraron ${cantidad}. ¿El clúster tiene la topología de 4 nodos del curso?"
  exit 1
fi

i=1
for w in $workers; do
  z=$(printf '%s' "$ZONAS" | cut -d' ' -f"$i")
  kubectl label node "$w" "topology.kubernetes.io/zone=${z}" --overwrite --context "$CONTEXTO" >/dev/null
  msg_ok "Worker ${w} -> zona ${z}"
  i=$((i + 1))
done

msg_ok "Los 3 workers están etiquetados con sus zonas."
msg_info "Verifica con: kubectl get nodes -L topology.kubernetes.io/zone"
