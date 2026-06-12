#!/usr/bin/env bash
# Recuperación del Lab 03: reconstruye el ESTADO FINAL (tópicos gestionados,
# clúster endurecido, usuarios con ACLs y cuotas, pod cliente) sin interacción.
# Encadena el 95 del Lab 02 y hereda el exit code del test 90 del Lab 03.
#
# LAB01_CLUSTER permite usar otro nombre de clúster.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
LAB02_95="$DIR_SCRIPT/../../lab-02-cluster-pagos/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
TIMEOUT_KAFKA="600s"

msg_info "Este script reconstruye el resultado del Lab 03 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 02 (clúster persistente + rack + tópico transacciones).
msg_info "Reconstruyendo primero el estado del Lab 02..."
if ! bash "$LAB02_95" >/tmp/lab03-lab02-95.out 2>&1; then
  msg_error "La recuperación del Lab 02 falló. Detalle:"
  tail -n 15 /tmp/lab03-lab02-95.out | sed 's/^/    /'
  exit 1
fi
msg_ok "Estado del Lab 02 reconstruido."

# Imagen de Kafka de un broker real (para los pods cliente efímeros).
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# 2. Tópico libre por CLI, ANTES de endurecer (el listener plano aún funciona).
msg_info "Creando el tópico no gestionado tmp.pruebas.libre por CLI..."
kubectl run "cli-tmp-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image="$IMG" --command -- bin/kafka-topics.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 --create --if-not-exists \
  --topic tmp.pruebas.libre --partitions 1 --replication-factor 3 >/dev/null 2>&1 || true

# 3. Tópicos gestionados (adopción de transacciones + confirmaciones nativo).
msg_info "Aplicando los KafkaTopics (adopción y nativo)..."
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/topics/"

# 4. Endurecimiento del clúster (listeners autenticados + authorization).
msg_info "Aplicando el clúster endurecido (rolling update)..."
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/kafka/"
msg_info "Esperando a que el clúster vuelva a Ready tras el rolling (máximo ${TIMEOUT_KAFKA})..."
if ! kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  msg_error "El clúster no volvió a Ready tras el endurecimiento. Revisa 'kubectl get pods -n ${NS}'."
  exit 1
fi

# 5. Usuarios con sus ACLs y cuota.
msg_info "Aplicando los KafkaUsers..."
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/users/"
for u in app-pagos motor-fraude; do
  kubectl wait --for=condition=Ready "kafkauser/${u}" -n "$NS" --context "$CONTEXTO" --timeout=180s || true
done

# 6. Pod cliente con credenciales montadas.
msg_info "Preparando el pod cliente..."
bash "$DIR_SCRIPT/01-preparar-cliente.sh"

# 7. Verificación final: hereda el exit code del test 90.
echo
msg_info "Ejecutando el test de estado del Lab 03 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
