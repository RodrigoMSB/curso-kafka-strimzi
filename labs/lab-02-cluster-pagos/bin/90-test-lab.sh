#!/usr/bin/env bash
# Test de estado del Lab 02. Verifica el estado FINAL (clúster persistente con
# rack). Solo lectura de infraestructura; la verificación 7 produce y consume un
# mensaje de humo (round-trip funcional) a propósito, como indica la spec.
#
# Contrato del molde: ejecuta todas las verificaciones, contadores dinámicos,
# una pista por cada [ERROR], exit 0 si todas pasan y 1 si alguna falla.
# LAB01_CLUSTER permite apuntar a otro clúster.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
BOOTSTRAP="pagos-kafka-bootstrap:9092"
TOPICO="pagos.meridiano.transacciones"
LAB01_90="$DIR_SCRIPT/../../lab-01-cimientos/bin/90-test-lab.sh"

total=0
aprobadas=0
verificar() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then
    aprobadas=$((aprobadas + 1)); msg_ok "$1"
  else
    msg_error "$1 -> $3"
  fi
}

msg_info "Test del Lab 02 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

# 1. El estado del Lab 01 sigue verde (operador instalado y vigilando).
if [ -f "$LAB01_90" ] && bash "$LAB01_90" >/tmp/lab02-lab01-90.out 2>&1; then r=0; else r=1; fi
verificar "Estado del Lab 01 intacto (su test 90 en verde)" "$r" \
  "Recupera el Lab 01: labs/lab-01-cimientos/bin/95-recuperar-lab.sh"

# 2. CR Kafka 'pagos' con condición Ready.
ready=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$ready" = "True" ]; then r=0; else r=1; fi
verificar "Clúster Kafka '${CLUSTER}' con status Ready" "$r" \
  "Revisa 'kubectl get kafka ${CLUSTER} -n ${NS} -o yaml' (sección status.conditions); ver guía 02 y troubleshooting."

# 3. Pods: 1 controller + 3 brokers, Running y listos.
listado=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"|"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"\n"}{end}' \
  2>/dev/null || true)
n_ctrl=0; n_brk=0; pods_mal=0
while IFS='|' read -r nombre fase listos; do
  case "$nombre" in
    pagos-controllers-*) etiqueta=ctrl ;;
    pagos-brokers-*)     etiqueta=brk ;;
    *) continue ;;
  esac
  [ "$etiqueta" = ctrl ] && n_ctrl=$((n_ctrl + 1))
  [ "$etiqueta" = brk ]  && n_brk=$((n_brk + 1))
  case "$listos" in *false*|,|"") pods_mal=$((pods_mal + 1)) ;; esac
  [ "$fase" != "Running" ] && pods_mal=$((pods_mal + 1))
done <<EOF
$listado
EOF
if [ "$n_ctrl" -eq 1 ] && [ "$n_brk" -eq 3 ] && [ "$pods_mal" -eq 0 ]; then r=0; else r=1; fi
verificar "Pods: 1 controller + 3 brokers, Running y listos (detectado ${n_ctrl}c/${n_brk}b)" "$r" \
  "Revisa 'kubectl get pods -n ${NS}'; pods Pending suelen ser recursos de Docker (troubleshooting)."

# 4. Storage: PVCs de los brokers en estado Bound.
pvc_bound=$(kubectl get pvc -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null \
  | grep 'brokers' | grep -c '|Bound' || true)
if [ "$pvc_bound" -ge 3 ]; then r=0; else r=1; fi
verificar "PVCs persistentes de los brokers en Bound (detectados ${pvc_bound})" "$r" \
  "Revisa 'kubectl get pvc -n ${NS}'; un PVC Pending suele ser la StorageClass (troubleshooting)."

# 5. Workers etiquetados con 3 zonas distintas.
zonas=$(kubectl get nodes --context "$CONTEXTO" -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' 2>/dev/null \
  | grep -c . || true)
zonas_distintas=$(kubectl get nodes --context "$CONTEXTO" -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{range .items[*]}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}' 2>/dev/null \
  | sort -u | grep -c . || true)
if [ "$zonas" -ge 3 ] && [ "$zonas_distintas" -ge 3 ]; then r=0; else r=1; fi
verificar "Los 3 workers etiquetados con 3 zonas distintas" "$r" \
  "Etiqueta las zonas con bin/01-etiquetar-zonas.sh (guía 05)."

# 6. Rack habilitado en el CR.
rack=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.spec.kafka.rack.topologyKey}' 2>/dev/null || true)
if [ -n "$rack" ]; then r=0; else r=1; fi
verificar "Rack awareness habilitado en el CR (topologyKey=${rack:-ausente})" "$r" \
  "Aplica la solución de la parte 2 (soluciones/parte-2-persistente/20-kafka-pagos.yaml); ver guía 05."

# Imagen de Kafka: la del broker real (evita adivinar el tag).
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# 6b. Tópico de pagos con RF=3 y 3 réplicas distintas por partición.
# Reintento: la primera consulta puede llegar antes de que el tópico propague
# su metadata a través del pod cliente recién creado.
desc=""
intento=1
while [ "$intento" -le 3 ]; do
  desc=$(kubectl run "cli-desc-$$-${intento}" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
    --image="$IMG" --command -- bin/kafka-topics.sh \
    --bootstrap-server "$BOOTSTRAP" --describe --topic "$TOPICO" 2>/dev/null || true)
  printf '%s\n' "$desc" | grep -q "ReplicationFactor:" && break
  intento=$((intento + 1))
  sleep 5
done
rf_ok=1
if printf '%s\n' "$desc" | grep -q "ReplicationFactor: 3"; then
  # Cada línea de partición debe listar 3 réplicas distintas.
  malas=$(printf '%s\n' "$desc" | sed -n 's/.*Replicas: \([0-9,]*\).*/\1/p' \
    | while IFS= read -r reps; do
        distintas=$(printf '%s' "$reps" | tr ',' '\n' | sort -u | grep -c .)
        [ "$distintas" -ne 3 ] && echo "x"
      done | grep -c x || true)
  [ "$malas" -eq 0 ] && rf_ok=0
fi
verificar "Tópico ${TOPICO} con RF=3 y réplicas en 3 brokers distintos" "$rf_ok" \
  "Crea el tópico con RF 3 (guía 03) y confirma rack/zonas (guía 05)."

# 7. Round-trip de humo: producir y consumir un mensaje único.
MARCA="humo-$(date +%s)-$$"
printf '%s\n' "$MARCA" | kubectl run "cli-prod-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image="$IMG" --command -- bin/kafka-console-producer.sh \
  --bootstrap-server "$BOOTSTRAP" --topic "$TOPICO" >/dev/null 2>&1 || true
consumido=$(kubectl run "cli-cons-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image="$IMG" --command -- bin/kafka-console-consumer.sh \
  --bootstrap-server "$BOOTSTRAP" --topic "$TOPICO" --from-beginning --timeout-ms 20000 2>/dev/null || true)
if printf '%s' "$consumido" | grep -q "$MARCA"; then r=0; else r=1; fi
verificar "Round-trip de humo: mensaje producido y consumido" "$r" \
  "Revisa que el listener plain (9092) responda y que el tópico exista (guía 03 / troubleshooting)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 02 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 02 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
