#!/usr/bin/env bash
# Recuperación del Lab 02: reconstruye el ESTADO FINAL del lab (clúster Kafka de
# pagos persistente, con rack y el tópico creado) sin interacción.
#
# Encadena el 95 del Lab 01 (clúster + operador) y luego despliega el ESTADO
# FINAL del Lab 02: los nodepools persistentes de soluciones/parte-2-persistente/
# más el Kafka con rack de soluciones/parte-3-rack/. Se declara exitoso solo si
# el test 90 del Lab 02 pasa: hereda su exit code.
#
# LAB01_CLUSTER permite usar otro nombre de clúster (consistente con el molde).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
BOOTSTRAP="pagos-kafka-bootstrap:9092"
TOPICO="pagos.meridiano.transacciones"
LAB01_95="$DIR_SCRIPT/../../lab-01-cimientos/bin/95-recuperar-lab.sh"
# Estado final = nodepools persistentes (parte 2) + Kafka con rack (parte 3).
# Los nodepools NO cambian entre la parte 2 y la 3: rack es un cambio solo en el
# Kafka CR, aplicable en caliente (ver guía 05).
SOL_PERSISTENTE="$DIR_SCRIPT/../soluciones/parte-2-persistente"
SOL_RACK="$DIR_SCRIPT/../soluciones/parte-3-rack"
TIMEOUT_KAFKA="600s"

msg_info "Este script reconstruye el resultado del Lab 02 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 01 (clúster + operador). Su 95 termina ejecutando su
#    propio test 90; si falla, no seguimos.
msg_info "Reconstruyendo primero el estado del Lab 01..."
if ! bash "$LAB01_95" >/tmp/lab02-lab01-95.out 2>&1; then
  msg_error "La recuperación del Lab 01 falló. Detalle:"
  tail -n 15 /tmp/lab02-lab01-95.out | sed 's/^/    /'
  exit 1
fi
msg_ok "Estado del Lab 01 reconstruido."

# 2. Etiquetar zonas ANTES de aplicar el clúster con rack.
bash "$DIR_SCRIPT/01-etiquetar-zonas.sh"

# 3. Aplicar el estado final: nodepools persistentes (parte 2) + Kafka con rack
#    (parte 3). El recuperador no separa los estados como las guías porque no
#    enseña: reconstruye el resultado en un solo paso.
msg_info "Aplicando el clúster de pagos (persistente + rack)..."
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL_PERSISTENTE"
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL_RACK"

# 4. Esperar a que el clúster Kafka esté Ready.
msg_info "Esperando a que el clúster Kafka esté Ready (máximo ${TIMEOUT_KAFKA}, la primera vez baja la imagen)..."
if kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  msg_ok "Clúster Kafka Ready."
else
  msg_error "El clúster Kafka no quedó Ready en ${TIMEOUT_KAFKA}."
  msg_error "Revisa 'kubectl get pods -n ${NS}' y docs/troubleshooting.md."
  exit 1
fi

# 5. Crear el tópico de pagos (idempotente). Imagen tomada de un broker real.
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"
msg_info "Asegurando el tópico ${TOPICO}..."
kubectl run "cli-topic-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image="$IMG" --command -- bin/kafka-topics.sh \
  --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
  --topic "$TOPICO" --partitions 3 --replication-factor 3 \
  --config min.insync.replicas=2 >/dev/null 2>&1 || true

# 6. Verificación final: hereda el exit code del test 90 del Lab 02.
echo
msg_info "Ejecutando el test de estado del Lab 02 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
