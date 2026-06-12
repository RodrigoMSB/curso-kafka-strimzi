#!/usr/bin/env bash
# Recuperación del Lab 06: reconstruye el ESTADO FINAL (clúster dr, MM2 replicando,
# métricas, Prometheus y Grafana) sin interacción. Encadena el 95 del Lab 05 y
# hereda el exit code del test 90 del Lab 06.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"; NSD="meridiano-dr"; NSSIS="meridiano-sistema"
LAB05_95="$DIR_SCRIPT/../../lab-05-cdc-core/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
MET="$DIR_SCRIPT/../infra/observabilidad/kafka-metrics-configmap.yaml"

msg_info "Este script reconstruye el resultado del Lab 06 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 05 (la cadena completa).
msg_info "Reconstruyendo primero el estado del Lab 05 (cadena completa)..."
if ! bash "$LAB05_95" >/tmp/lab06-lab05-95.out 2>&1; then
  msg_error "La recuperación del Lab 05 falló. Detalle:"; tail -n 15 /tmp/lab06-lab05-95.out | sed 's/^/    /'; exit 1
fi
msg_ok "Estado del Lab 05 reconstruido."

# 2. Ampliar el scope del operador para vigilar meridiano-dr (gobernanza).
kubectl apply --context "$CONTEXTO" -f "$SOL/dr/10-namespace.yaml"
msg_info "Ampliando el scope del operador (watchNamespaces += meridiano-dr)..."
helm upgrade strimzi-operator strimzi/strimzi-kafka-operator --version 0.51.0 \
  -n "$NSSIS" --kube-context "$CONTEXTO" --reuse-values \
  --set 'watchNamespaces={meridiano-pagos,meridiano-dr}' >/dev/null
kubectl rollout status deployment/strimzi-cluster-operator -n "$NSSIS" --context "$CONTEXTO" --timeout=180s

# 3. Clúster DR.
msg_info "Desplegando el clúster de contingencia 'dr'..."
kubectl apply --context "$CONTEXTO" -f "$SOL/dr/20-kafka-dr.yaml"
kubectl wait --for=condition=Ready kafka/dr -n "$NSD" --context "$CONTEXTO" --timeout=600s

# 4. Usuario mm2 + MirrorMaker 2.
kubectl apply --context "$CONTEXTO" -f "$SOL/mm2/10-kafkauser-mm2.yaml"
kubectl wait --for=condition=Ready kafkauser/mm2 -n "$NSP" --context "$CONTEXTO" --timeout=180s || true
msg_info "Desplegando MirrorMaker 2 (pagos -> dr)..."
kubectl apply --context "$CONTEXTO" -f "$SOL/mm2/20-mirrormaker2.yaml"
kubectl wait --for=condition=Ready kafkamirrormaker2/pagos-a-dr -n "$NSP" --context "$CONTEXTO" --timeout=600s || true

# 5. Métricas en pagos (rolling) + 6. Observabilidad.
msg_info "Habilitando métricas en pagos (rolling)..."
kubectl apply --context "$CONTEXTO" -f "$MET"
kubectl apply --context "$CONTEXTO" -f "$SOL/observabilidad/00-kafka-pagos-metrics.yaml"
kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s
bash "$DIR_SCRIPT/01-desplegar-observabilidad.sh"

# 7. Verificación final.
echo
msg_info "Ejecutando el test de estado del Lab 06 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
