#!/usr/bin/env bash
# Recuperación del Lab 05: reconstruye el ESTADO FINAL (registry, core PostgreSQL,
# Kafka Connect con Debezium construido, conector capturando) sin interacción.
# Encadena el 95 del Lab 04 y hereda el exit code del test 90 del Lab 05.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
LAB04_95="$DIR_SCRIPT/../../lab-04-puerta-segura/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones/connect"
TIMEOUT_CONNECT="900s"

msg_info "Este script reconstruye el resultado del Lab 05 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 04.
msg_info "Reconstruyendo primero el estado del Lab 04..."
if ! bash "$LAB04_95" >/tmp/lab05-lab04-95.out 2>&1; then
  msg_error "La recuperación del Lab 04 falló. Detalle:"
  tail -n 15 /tmp/lab05-lab04-95.out | sed 's/^/    /'
  exit 1
fi
msg_ok "Estado del Lab 04 reconstruido."

# 2. Registry local + 3. Core PostgreSQL.
bash "$DIR_SCRIPT/01-registry-local.sh"
bash "$DIR_SCRIPT/02-desplegar-core.sh"

# 4. Identidades y credencial de la BD.
msg_info "Aplicando Secret de la BD y KafkaUsers de Connect..."
kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/10-connect-db-cred.yaml"
kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/20-kafkauser-connect.yaml"
kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/25-kafkauser-cdc-reader.yaml"
for u in connect-cdc cdc-reader; do
  kubectl wait --for=condition=Ready "kafkauser/${u}" -n "$NSP" --context "$CONTEXTO" --timeout=180s || true
done

# 5. KafkaConnect con build (construye la imagen con Debezium: TARDA minutos).
msg_info "Aplicando KafkaConnect (el build con Debezium puede tardar varios minutos)..."
kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/30-kafkaconnect.yaml"
if ! kubectl wait --for=condition=Ready "kafkaconnect/connect-cdc" -n "$NSP" --context "$CONTEXTO" --timeout="$TIMEOUT_CONNECT"; then
  msg_error "KafkaConnect no quedó Ready (¿build fallido?). Revisa el pod connect-cdc-connect-build y docs/troubleshooting.md."
  exit 1
fi

# 6. El conector (el encargo).
msg_info "Aplicando el KafkaConnector..."
kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/40-kafkaconnector.yaml"
kubectl wait --for=condition=Ready "kafkaconnector/core-clientes" -n "$NSP" --context "$CONTEXTO" --timeout=300s || true

# 7. Verificación final: hereda el exit code del test 90.
echo
msg_info "Ejecutando el test de estado del Lab 05 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
