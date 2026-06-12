#!/usr/bin/env bash
# Test end-to-end del Lab 05 (INSTRUCTOR). Certifica de cero a fin encadenando
# Lab 01 -> 05, CON BUILD REAL de la imagen de Connect (la corrida más larga del
# curso). LAB05_E2E_CLUSTER=<nombre> para otro clúster; --conservar para no destruir.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB05_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NSP="meridiano-pagos"
LAB04_95="$DIR_SCRIPT/../../lab-04-puerta-segura/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones/connect"
TIMEOUT_CONNECT="900s"

CONSERVAR=0
[ "${1:-}" = "--conservar" ] && CONSERVAR=1
LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab05-e2e.XXXXXX")"
trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"; res_f5="-"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() { echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"; msg_error "Últimas líneas:"; tail -n 25 "$LOG_PASO" | sed 's/^/    /'; }
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
  msg_info "Duración total: ${dur}s ($((dur/60)) min)"
  msg_info "Fase 0 (guardia):            ${res_f0}"
  msg_info "Fase 1 (estado Lab 04):      ${res_f1}"
  msg_info "Fase 2 (registry + core):    ${res_f2}"
  msg_info "Fase 3 (Connect build + conector): ${res_f3}"
  msg_info "Fase 4 (verificación 90):    ${res_f4}"
  msg_info "Fase 5 (limpieza):           ${res_f5}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el Lab 05 funciona en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}

# Fase 0
msg_info "===== Fase 0: guardia (certificación desde cero) ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"
  msg_error "Ya existe un clúster '${CLUSTER_E2E}'. Destrúyelo (LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh) o usa LAB05_E2E_CLUSTER=otro."
  res_f5="omitida (clúster preexistente)"; finalizar 1 "Fase 0 (clúster preexistente)"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo. Continuamos."

# Fase 1: Lab 04
echo; msg_info "===== Fase 1: estado del Lab 04 ====="
if correr bash "$LAB04_95"; then res_f1="OK"; msg_ok "Estado del Lab 04 reconstruido."
else res_f1="FALLO"; reportar_fallo 1 "bash ../../lab-04-puerta-segura/bin/95-recuperar-lab.sh"; limpieza_cluster; finalizar 1 "Fase 1 (estado del Lab 04)"; fi

# Fase 2: registry + core
echo; msg_info "===== Fase 2: registry local + core PostgreSQL ====="
if ! correr bash "$DIR_SCRIPT/01-registry-local.sh"; then res_f2="FALLO"; reportar_fallo 2 "bash bin/01-registry-local.sh"; limpieza_cluster; finalizar 1 "Fase 2 (registry)"; fi
if ! correr bash "$DIR_SCRIPT/02-desplegar-core.sh"; then res_f2="FALLO"; reportar_fallo 2 "bash bin/02-desplegar-core.sh"; limpieza_cluster; finalizar 1 "Fase 2 (core)"; fi
res_f2="OK"; msg_ok "Registry y core listos."

# Fase 3: Connect build + conector
echo; msg_info "===== Fase 3: Kafka Connect (build con Debezium) + conector ====="
correr kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/10-connect-db-cred.yaml"
correr kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/20-kafkauser-connect.yaml"
correr kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/25-kafkauser-cdc-reader.yaml"
for u in connect-cdc cdc-reader; do
  correr kubectl wait --for=condition=Ready "kafkauser/${u}" -n "$NSP" --context "$CONTEXTO" --timeout=180s || true
done
if ! correr kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/30-kafkaconnect.yaml"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl apply kafkaconnect"; limpieza_cluster; finalizar 1 "Fase 3 (aplicar KafkaConnect)"
fi
msg_info "Esperando el build + arranque de Connect (hasta ${TIMEOUT_CONNECT})..."
if ! correr kubectl wait --for=condition=Ready "kafkaconnect/connect-cdc" -n "$NSP" --context "$CONTEXTO" --timeout="$TIMEOUT_CONNECT"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl wait kafkaconnect/connect-cdc (build)"; limpieza_cluster; finalizar 1 "Fase 3 (KafkaConnect no Ready / build fallido)"
fi
if ! correr kubectl apply -n "$NSP" --context "$CONTEXTO" -f "$SOL/40-kafkaconnector.yaml"; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl apply kafkaconnector"; limpieza_cluster; finalizar 1 "Fase 3 (aplicar KafkaConnector)"
fi
if ! correr kubectl wait --for=condition=Ready "kafkaconnector/core-clientes" -n "$NSP" --context "$CONTEXTO" --timeout=300s; then
  res_f3="FALLO"; reportar_fallo 3 "kubectl wait kafkaconnector/core-clientes"; limpieza_cluster; finalizar 1 "Fase 3 (KafkaConnector no Ready)"
fi
res_f3="OK"; msg_ok "Connect construido y conector capturando."

# Fase 4: verificación
echo; msg_info "===== Fase 4: verificación (test 90, round-trip CDC) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then res_f4="OK"; msg_ok "Verificación superada."
else res_f4="FALLO"; reportar_fallo 4 "bash bin/90-test-lab.sh"; limpieza_cluster; finalizar 1 "Fase 4 (verificación)"; fi

# Fase 5: limpieza + veredicto
limpieza_cluster
if [ "$res_f5" = "FALLO" ]; then finalizar 1 "Fase 5 (limpieza)"; else finalizar 0 ""; fi
