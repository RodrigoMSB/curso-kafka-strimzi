#!/usr/bin/env bash
# Test de estado del Lab 06 (contingencia + ojos). Contrato del molde.
# Checks insignia: round-trip de réplica (pagos -> dr) y métrica viva en Prometheus.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"; NSD="meridiano-dr"; NSO="meridiano-observabilidad"
TOPICO="pagos.meridiano.transacciones"
LAB05_90="$DIR_SCRIPT/../../lab-05-cdc-core/bin/90-test-lab.sh"

total=0; aprobadas=0
verificar() { total=$((total+1)); if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas+1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi; }

msg_info "Test del Lab 06 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo
IMG=$(kubectl get pods -n "$NSP" --context "$CONTEXTO" -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# 1. Estado del Lab 05 (CDC) intacto.
if [ -f "$LAB05_90" ] && bash "$LAB05_90" >/tmp/lab06-lab05-90.out 2>&1; then r=0; else r=1; fi
verificar "Estado del Lab 05 intacto (su test 90 en verde)" "$r" "Recupera con bin/95-recuperar-lab.sh"

# 2. Clúster DR Ready (1 nodo dual-role).
drready=$(kubectl get kafka dr -n "$NSD" --context "$CONTEXTO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
drpods=$(kubectl get pods -n "$NSD" --context "$CONTEXTO" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c '^dr-.*|Running' || true)
if [ "$drready" = "True" ] && [ "$drpods" -ge 1 ]; then r=0; else r=1; fi
verificar "Clúster DR Ready en meridiano-dr (pods Running=${drpods})" "$r" "Amplía el scope del operador y aplica el DR (guía 02)."

# 3. MM2 Ready + round-trip de réplica: produce en pagos -> aparece en dr.
mm2ready=$(kubectl get kafkamirrormaker2 pagos-a-dr -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
MARCA="repl-$(date +%s)-$$"
kubectl exec cliente-kafka -n "$NSP" --context "$CONTEXTO" -- bash -c "echo '${MARCA}' | bin/kafka-console-producer.sh --bootstrap-server pagos-kafka-bootstrap:9094 --producer.config /props/app-pagos.properties --topic ${TOPICO}" >/dev/null 2>&1 || true
repl=""
intento=1
while [ "$intento" -le 4 ]; do
  repl=$(kubectl run "dr-cons-$$-${intento}" --rm -i --restart=Never -n "$NSD" --context "$CONTEXTO" --image="$IMG" --command -- \
    bin/kafka-console-consumer.sh --bootstrap-server dr-kafka-bootstrap.meridiano-dr.svc:9092 --topic "$TOPICO" --from-beginning --timeout-ms 25000 2>/dev/null || true)
  printf '%s' "$repl" | grep -q "$MARCA" && break
  intento=$((intento+1))
done
if [ "$mm2ready" = "True" ] && printf '%s' "$repl" | grep -q "$MARCA"; then r=0; else r=1; fi
verificar "MM2 Ready y round-trip de réplica (pagos -> dr) del mensaje marcado" "$r" \
  "Revisa el MM2 Ready, las ACLs del usuario mm2 y la replication policy (guías 03-04 / troubleshooting)."

# Consulta de observabilidad (un solo pod con curl).
obs=$(kubectl run "obs-check-$$" --rm -i --restart=Never -n "$NSO" --context "$CONTEXTO" --image="$IMG" --command -- bash -c '
  echo "===UP==="; curl -s "http://prometheus.meridiano-observabilidad.svc:9090/api/v1/query?query=up%7Bjob%3D%22strimzi-pods%22%7D"
  echo; echo "===METRIC==="; curl -s "http://prometheus.meridiano-observabilidad.svc:9090/api/v1/query?query=kafka_server_replicamanager_partitioncount"
  echo; echo "===GRAFANA==="; curl -s "http://grafana.meridiano-observabilidad.svc:3000/api/health"
' 2>/dev/null || true)

# 4. Prometheus scrapeando Kafka (targets up) y Grafana respondiendo.
up_section=$(printf '%s' "$obs" | sed -n '/===UP===/,/===METRIC===/p')
graf_section=$(printf '%s' "$obs" | sed -n '/===GRAFANA===/,$p')
if printf '%s' "$up_section" | grep -q ',"1"]' && printf '%s' "$graf_section" | grep -qi '"database":"ok"\|ok'; then r=0; else r=1; fi
verificar "Prometheus scrapeando Kafka (targets up) y Grafana respondiendo" "$r" \
  "Despliega la observabilidad (bin/01-desplegar-observabilidad.sh) y revisa metricsConfig en pagos (guía 05)."

# 5. Métrica viva: una métrica de Kafka devuelve series con datos.
metric_section=$(printf '%s' "$obs" | sed -n '/===METRIC===/,/===GRAFANA===/p')
if printf '%s' "$metric_section" | grep -q '"result":\[{'; then r=0; else r=1; fi
verificar "Métrica de Kafka viva en Prometheus (devuelve series con datos)" "$r" \
  "Confirma metricsConfig en el CR de pagos y que Prometheus scrapea el puerto tcp-prometheus (guía 05/06)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 06 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 06 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
