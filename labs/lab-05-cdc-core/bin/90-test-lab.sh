#!/usr/bin/env bash
# Test de estado del Lab 05 (CDC del core). Contrato del molde.
# El check insignia (4-5) hace un round-trip CDC real: INSERT en PostgreSQL ->
# evento en core.public.clientes, consumido como cdc-reader.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
NSC="meridiano-core"
LAB04_90="$DIR_SCRIPT/../../lab-04-puerta-segura/bin/90-test-lab.sh"

total=0; aprobadas=0
verificar() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas + 1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi
}

msg_info "Test del Lab 05 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

IMG=$(kubectl get pods -n "$NSP" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# 1. Estado del Lab 04 (puerta segura) intacto.
if [ -f "$LAB04_90" ] && bash "$LAB04_90" >/tmp/lab05-lab04-90.out 2>&1; then r=0; else r=1; fi
verificar "Estado del Lab 04 intacto (su test 90 en verde)" "$r" \
  "Recupera con bin/95-recuperar-lab.sh"

# 2. Registry local + core PostgreSQL Ready con la tabla.
reg_ok=1; [ -n "$(docker ps -q -f name='^kind-registry$')" ] && reg_ok=0
pg_count=$(kubectl exec -n "$NSC" --context "$CONTEXTO" deploy/core-postgres -- \
  psql -U postgres -d meridiano -tAc "SELECT count(*) FROM clientes" 2>/dev/null | tr -d '[:space:]' || true)
if [ "$reg_ok" -eq 0 ] && [ -n "$pg_count" ] && [ "$pg_count" -ge 3 ] 2>/dev/null; then r=0; else r=1; fi
verificar "Registry local corriendo y core PostgreSQL Ready con la tabla (filas=${pg_count:-?})" "$r" \
  "Crea el registry (bin/01-registry-local.sh) y el core (bin/02-desplegar-core.sh)."

# 3. connect-cdc user Ready, KafkaConnect Ready, KafkaConnector con task RUNNING.
ku=$(kubectl get kafkauser connect-cdc -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
kc=$(kubectl get kafkaconnect connect-cdc -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
kctor=$(kubectl get kafkaconnector core-clientes -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.connectorStatus.connector.state}' 2>/dev/null || true)
ktask=$(kubectl get kafkaconnector core-clientes -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.tasksMax}{" "}{.status.connectorStatus.tasks[0].state}' 2>/dev/null || true)
if [ "$ku" = "True" ] && [ "$kc" = "True" ] && [ "$kctor" = "RUNNING" ]; then r=0; else r=1; fi
verificar "connect-cdc/KafkaConnect Ready y KafkaConnector RUNNING (conector=${kctor:-?})" "$r" \
  "Revisa el build (guía 03) y el status del KafkaConnector (guía 04)."

# Round-trip CDC: INSERT marcado en PostgreSQL -> evento en core.public.clientes.
MARCA="cdc-$(date +%s)-$$"
kubectl exec -n "$NSC" --context "$CONTEXTO" deploy/core-postgres -- \
  psql -U postgres -d meridiano -c \
  "INSERT INTO clientes (nombre, email, saldo) VALUES ('${MARCA}','${MARCA}@meridiano.cl', 1.00)" >/dev/null 2>&1 || true

PW_CDC=$(kubectl get secret cdc-reader -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.data.password}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)
evento=$(kubectl run "cdc-cons-$$" --rm -i --restart=Never -n "$NSP" --context "$CONTEXTO" \
  --image="$IMG" --command -- bash -c "
    printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"cdc-reader\" password=\"${PW_CDC}\";\n' > /tmp/c.properties
    bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9094 \
      --command-config /tmp/c.properties --topic core.public.clientes \
      --group cdc-reader-g --from-beginning --timeout-ms 40000
  " 2>/dev/null || true)

# 4. El evento del INSERT marcado llegó al tópico de CDC.
if printf '%s' "$evento" | grep -q "$MARCA"; then r=0; else r=1; fi
verificar "Round-trip CDC: el INSERT en PostgreSQL apareció en core.public.clientes" "$r" \
  "Revisa el conector RUNNING y las ACLs/credenciales (guías 03-04 / troubleshooting)."

# 5. El sobre del evento contiene op y after coherentes.
linea=$(printf '%s\n' "$evento" | grep "$MARCA" | head -1)
if printf '%s' "$linea" | grep -q '"op"' && printf '%s' "$linea" | grep -q '"after"'; then r=0; else r=1; fi
verificar "El sobre del evento contiene 'op' y 'after' (forma de Debezium)" "$r" \
  "El conector debe emitir el sobre Debezium; revisa los converters (guía 04)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 05 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 05 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
