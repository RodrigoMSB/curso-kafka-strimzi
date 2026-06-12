#!/usr/bin/env bash
# Plomería de observabilidad: Prometheus (standalone) + Grafana con el dashboard
# oficial de Strimzi. Idempotente. El ConfigMap del dashboard se crea desde el
# JSON descargado del tag 0.51.0 (infra/observabilidad/strimzi-kafka-dashboard.json).
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
OBS="$DIR_SCRIPT/../soluciones/observabilidad"
DASH="$DIR_SCRIPT/../infra/observabilidad/strimzi-kafka-dashboard.json"
NSO="meridiano-observabilidad"

msg_info "Desplegando Prometheus..."
kubectl apply --context "$CONTEXTO" -f "$OBS/10-prometheus.yaml"

# Dashboard como ConfigMap (antes de Grafana, para que lo monte al arrancar).
if [ -f "$DASH" ]; then
  kubectl create configmap grafana-dashboard-kafka -n "$NSO" --context "$CONTEXTO" \
    --from-file="strimzi-kafka.json=${DASH}" --dry-run=client -o yaml \
    | kubectl apply --context "$CONTEXTO" -f -
else
  msg_error "No se encontró el dashboard JSON en ${DASH}."
fi

msg_info "Desplegando Grafana..."
kubectl apply --context "$CONTEXTO" -f "$OBS/20-grafana.yaml"

msg_info "Esperando a que Prometheus y Grafana estén listos (máximo 180s c/u)..."
kubectl rollout status deployment/prometheus -n "$NSO" --context "$CONTEXTO" --timeout=180s
kubectl rollout status deployment/grafana -n "$NSO" --context "$CONTEXTO" --timeout=180s

msg_ok "Observabilidad lista."
msg_info "UIs (en otra terminal):"
msg_info "  kubectl port-forward -n ${NSO} svc/prometheus 9090:9090   # http://localhost:9090"
msg_info "  kubectl port-forward -n ${NSO} svc/grafana 3000:3000      # http://localhost:3000"
