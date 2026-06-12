#!/usr/bin/env bash
# Test end-to-end del Lab 03 (INSTRUCTOR). Certifica de cero a fin encadenando
# Lab 01 -> 02 -> 03, ejecuta de verdad la demo de drift, y limpia.
#
# LAB03_E2E_CLUSTER=<nombre> certifica con otro clúster (se propaga vía
# LAB01_CLUSTER). Flag --conservar: no destruir al final.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB03_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NS="meridiano-pagos"
CLUSTER="pagos"
TOPICO="pagos.meridiano.transacciones"
LAB02_95="$DIR_SCRIPT/../../lab-02-cluster-pagos/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
TIMEOUT_KAFKA="600s"

CONSERVAR=0
[ "${1:-}" = "--conservar" ] && CONSERVAR=1

LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab03-e2e.XXXXXX")"
trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"; res_f5="-"
drift_resultado="(no ejecutada)"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() {
  echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"
  msg_error "Últimas líneas:"; tail -n 20 "$LOG_PASO" | sed 's/^/    /'
}
img_broker() {
  kubectl get pods -n "$NS" --context "$CONTEXTO" \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
    | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2
}
limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f5="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado. Destrúyelo con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"
    return 0
  fi
  echo; msg_info "===== Fase 5: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then res_f5="OK"; else res_f5="FALLO"; fi
}
finalizar() {
  fin=$(date +%s); dur=$((fin - INICIO))
  echo; msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s"
  msg_info "Fase 0 (guardia):            ${res_f0}"
  msg_info "Fase 1 (estado Lab 02):      ${res_f1}"
  msg_info "Fase 2 (tópicos + drift):    ${res_f2}"
  msg_info "Fase 3 (endurecer + users):  ${res_f3}"
  msg_info "Fase 4 (verificación 90):    ${res_f4}"
  msg_info "Fase 5 (limpieza):           ${res_f5}"
  msg_info "Demo de drift (observada):   ${drift_resultado}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el Lab 03 funciona en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}

# Demo de drift: NO gatea el veredicto; observa y registra el comportamiento real.
demo_drift() {
  local img antes despues t ta
  img=$(img_broker); [ -z "$img" ] && img="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"
  kubectl run cli-admin --restart=Never -n "$NS" --context "$CONTEXTO" --image="$img" --command -- sleep 600 >/dev/null 2>&1 || true
  kubectl wait --for=condition=Ready pod/cli-admin -n "$NS" --context "$CONTEXTO" --timeout=60s >/dev/null 2>&1 || true
  # El valor DECLARADO en el KafkaTopic (inmediato, desde el CR).
  local declarada
  declarada=$(kubectl get kafkatopic "$TOPICO" -n "$NS" --context "$CONTEXTO" \
    -o jsonpath='{.spec.config.retention\.ms}' 2>/dev/null)
  # El valor REAL en Kafka antes de alterar (sondeo corto). Nota: el Topic
  # Operator unidireccional marca el KafkaTopic Ready en la adopción pero aplica
  # la config declarada a Kafka en su reconciliación periódica posterior, así que
  # puede que aún no esté presente aquí; eso es justo lo que la demo evidencia.
  antes=""; ta=0
  while [ "$ta" -lt 30 ]; do
    antes=$(kubectl exec cli-admin -n "$NS" --context "$CONTEXTO" -- bin/kafka-configs.sh \
      --bootstrap-server pagos-kafka-bootstrap:9092 --describe --entity-type topics \
      --entity-name "$TOPICO" 2>/dev/null | grep -o 'retention.ms=[0-9]*' | head -1)
    [ -n "$antes" ] && break
    sleep 5; ta=$((ta + 5))
  done
  msg_info "[drift] retención declarada en el KafkaTopic = retention.ms=${declarada:-?}; en Kafka antes de alterar = ${antes:-aún no aplicada por el operador}; alterando por CLI a 3600000..."
  kubectl exec cli-admin -n "$NS" --context "$CONTEXTO" -- bin/kafka-configs.sh \
    --bootstrap-server pagos-kafka-bootstrap:9092 --alter --entity-type topics \
    --entity-name "$TOPICO" --add-config retention.ms=3600000 >/dev/null 2>&1 || true
  t=0; despues=""
  while [ "$t" -lt 180 ]; do
    sleep 10; t=$((t + 10))
    despues=$(kubectl exec cli-admin -n "$NS" --context "$CONTEXTO" -- bin/kafka-configs.sh \
      --bootstrap-server pagos-kafka-bootstrap:9092 --describe --entity-type topics \
      --entity-name "$TOPICO" 2>/dev/null | grep -o 'retention.ms=[0-9]*' | head -1)
    if [ "$despues" = "retention.ms=604800000" ]; then
      drift_resultado="REVERTIDO a 604800000 en ~${t}s (Topic Operator)"
      break
    fi
    drift_resultado="NO revertido tras ${t}s (último=${despues:-?})"
  done
  msg_info "[drift] ${drift_resultado}"
  kubectl delete pod cli-admin -n "$NS" --context "$CONTEXTO" --grace-period=1 >/dev/null 2>&1 || true
}

# ===================== Fase 0 =====================
msg_info "===== Fase 0: guardia (certificación desde cero) ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"
  msg_error "Ya existe un clúster '${CLUSTER_E2E}'. Destrúyelo (LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh) o usa LAB03_E2E_CLUSTER=otro."
  res_f5="omitida (clúster preexistente)"
  finalizar 1 "Fase 0 (clúster '${CLUSTER_E2E}' preexistente)"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo. Continuamos."

# ===================== Fase 1: estado del Lab 02 =====================
echo; msg_info "===== Fase 1: estado del Lab 02 ====="
if correr bash "$LAB02_95"; then res_f1="OK"; msg_ok "Estado del Lab 02 reconstruido."
else res_f1="FALLO"; reportar_fallo 1 "bash ../../lab-02-cluster-pagos/bin/95-recuperar-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 1 (estado del Lab 02)"; fi

# ===================== Fase 2: tópicos como código + drift =====================
echo; msg_info "===== Fase 2: tópicos como código + demo de drift ====="
IMG=$(img_broker); [ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# Tópico libre por CLI (plano, antes de endurecer).
if ! correr kubectl run "cli-tmp-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
       --image="$IMG" --command -- bin/kafka-topics.sh \
       --bootstrap-server pagos-kafka-bootstrap:9092 --create --if-not-exists \
       --topic tmp.pruebas.libre --partitions 1 --replication-factor 3; then
  res_f2="FALLO"; reportar_fallo 2 "kafka-topics --create tmp.pruebas.libre"
  limpieza_cluster; finalizar 1 "Fase 2 (tópico libre)"
fi

# Confirmar que tmp.pruebas.libre existe (ANONYMOUS aún puede, sin authorization).
if ! correr kubectl run "cli-ls-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
       --image="$IMG" --command -- bin/kafka-topics.sh \
       --bootstrap-server pagos-kafka-bootstrap:9092 --list; then
  res_f2="FALLO"; reportar_fallo 2 "kafka-topics --list"
  limpieza_cluster; finalizar 1 "Fase 2 (listar tópicos)"
fi

# Tópicos gestionados (adopción + nativo).
if ! correr kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/topics/"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl apply -f soluciones/topics"
  limpieza_cluster; finalizar 1 "Fase 2 (aplicar KafkaTopics)"
fi
for t in pagos.meridiano.transacciones pagos.meridiano.confirmaciones; do
  if ! correr kubectl wait --for=condition=Ready "kafkatopic/${t}" -n "$NS" --context "$CONTEXTO" --timeout=120s; then
    res_f2="FALLO"; reportar_fallo 2 "kubectl wait kafkatopic/${t}"
    limpieza_cluster; finalizar 1 "Fase 2 (KafkaTopic ${t} no Ready)"
  fi
done

# Demo de drift (no gatea el veredicto).
demo_drift
res_f2="OK"; msg_ok "Tópicos gestionados y demo de drift ejecutada."

# ===================== Fase 3: endurecer + usuarios + cliente =====================
echo; msg_info "===== Fase 3: endurecer + usuarios + cliente ====="
if ! correr kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/kafka/"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl apply -f soluciones/kafka"
  limpieza_cluster; finalizar 1 "Fase 3 (aplicar Kafka endurecido)"
fi
if ! correr kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl wait kafka/${CLUSTER} (tras endurecer)"
  limpieza_cluster; finalizar 1 "Fase 3 (clúster no Ready tras endurecer)"
fi
if ! correr kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/users/"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl apply -f soluciones/users"
  limpieza_cluster; finalizar 1 "Fase 3 (aplicar KafkaUsers)"
fi
for u in app-pagos motor-fraude; do
  if ! correr kubectl wait --for=condition=Ready "kafkauser/${u}" -n "$NS" --context "$CONTEXTO" --timeout=180s; then
    res_f3="FALLO"; reportar_fallo 3 "kubectl wait kafkauser/${u}"
    limpieza_cluster; finalizar 1 "Fase 3 (KafkaUser ${u} no Ready)"
  fi
done
if ! correr bash "$DIR_SCRIPT/01-preparar-cliente.sh"; then
  res_f3="FALLO"; reportar_fallo 3 "bash bin/01-preparar-cliente.sh"
  limpieza_cluster; finalizar 1 "Fase 3 (preparar cliente)"
fi
res_f3="OK"; msg_ok "Clúster endurecido, usuarios y cliente listos."

# ===================== Fase 4: verificación =====================
echo; msg_info "===== Fase 4: verificación (test 90) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then res_f4="OK"; msg_ok "Verificación superada."
else res_f4="FALLO"; reportar_fallo 4 "bash bin/90-test-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 4 (verificación de estado)"; fi

# ===================== Fase 5: limpieza + veredicto =====================
limpieza_cluster
if [ "$res_f5" = "FALLO" ]; then finalizar 1 "Fase 5 (limpieza)"; else finalizar 0 ""; fi
