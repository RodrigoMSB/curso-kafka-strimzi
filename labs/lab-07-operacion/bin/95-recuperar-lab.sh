#!/usr/bin/env bash
# Recuperación del Lab 07: reconstruye el ESTADO FINAL (Cruise Control en pagos,
# historia de rebalanceo add/remove en estado Ready, pool de brokers de vuelta a
# 3). Encadena el 95 del Lab 06 y hereda el exit code del test 90 del Lab 07.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
LAB06_95="$DIR_SCRIPT/../../lab-06-contingencia-ojos/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"

msg_info "Este script reconstruye el resultado del Lab 07 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 06 (la cadena completa).
msg_info "Reconstruyendo primero el estado del Lab 06 (cadena completa)..."
if ! bash "$LAB06_95" >/tmp/lab07-lab06-95.out 2>&1; then
  msg_error "La recuperación del Lab 06 falló. Detalle:"; tail -n 15 /tmp/lab07-lab06-95.out | sed 's/^/    /'; exit 1
fi
msg_ok "Estado del Lab 06 reconstruido."

# 2. Habilitar Cruise Control en pagos (rolling + pod nuevo).
msg_info "Habilitando Cruise Control en pagos (rolling)..."
kubectl apply --context "$CONTEXTO" -f "$SOL/cruise-control/00-kafka-pagos-cc.yaml"
kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s

# 3. Crecer: escalar brokers a 4.
msg_info "Escalando el pool de brokers a 4..."
kubectl apply --context "$CONTEXTO" -f "$SOL/rebalance/05-nodepool-brokers-4.yaml"
kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s

# 4. Rebalance add-brokers: propuesta -> aprobar -> ejecutar (robusto).
msg_info "Rebalance add-brokers (Cruise Control necesita su ventana de métricas)..."
rebalance_completo agregar-broker-4 "$SOL/rebalance/10-add-brokers.yaml" "$CONTEXTO" "$NSP"
msg_ok "Rebalance add-brokers completado."

# 5. Rebalance remove-brokers (vaciar el broker 4).
msg_info "Rebalance remove-brokers..."
rebalance_completo vaciar-broker-4 "$SOL/rebalance/20-remove-brokers.yaml" "$CONTEXTO" "$NSP"
msg_ok "Rebalance remove-brokers completado."

# 6. Encoger: escalar brokers de vuelta a 3 (estado canónico).
msg_info "Escalando el pool de brokers de vuelta a 3 (estado canónico)..."
kubectl apply --context "$CONTEXTO" -f "$SOL/rebalance/25-nodepool-brokers-3.yaml"
kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s

# 7. Verificación final.
echo
msg_info "Ejecutando el test de estado del Lab 07 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
