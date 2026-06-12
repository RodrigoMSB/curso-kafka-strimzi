#!/usr/bin/env bash
# Test end-to-end del Lab 06 (INSTRUCTOR). La corrida TOTAL del curso: cadena
# Lab 01->06 con DR, MM2 y observabilidad. Mide el PICO DE MEMORIA del Docker VM.
# LAB06_E2E_CLUSTER=<nombre>; --conservar para no destruir.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB06_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NSP="meridiano-pagos"; NSD="meridiano-dr"; NSSIS="meridiano-sistema"
LAB05_95="$DIR_SCRIPT/../../lab-05-cdc-core/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
MET="$DIR_SCRIPT/../infra/observabilidad/kafka-metrics-configmap.yaml"

CONSERVAR=0; [ "${1:-}" = "--conservar" ] && CONSERVAR=1
LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab06-e2e.XXXXXX")"; trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"; res_f5="-"
mem_total="?"; mem_uso="?"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() { echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"; msg_error "Últimas líneas:"; tail -n 25 "$LOG_PASO" | sed 's/^/    /'; }
limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f5="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado. Destrúyelo con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"; return 0
  fi
  echo; msg_info "===== Fase 6: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then res_f5="OK"; else res_f5="FALLO"; fi
}
finalizar() {
  fin=$(date +%s); dur=$((fin-INICIO))
  echo; msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s ($((dur/60)) min)"
  msg_info "PICO DE MEMORIA Docker VM en máxima carga: ~${mem_uso} MiB de ~${mem_total} MiB totales"
  msg_info "Fase 0 (guardia): ${res_f0} | F1 (Lab 05): ${res_f1} | F2 (DR): ${res_f2}"
  msg_info "F3 (MM2): ${res_f3} | F4 (observabilidad): ${res_f4} | F6 (limpieza): ${res_f5}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el Lab 06 funciona en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}

# Fase 0
msg_info "===== Fase 0: guardia ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"; msg_error "Ya existe '${CLUSTER_E2E}'. Destrúyelo o usa LAB06_E2E_CLUSTER=otro."
  res_f5="omitida"; finalizar 1 "Fase 0 (clúster preexistente)"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo."

# Fase 1: cadena Lab 05
echo; msg_info "===== Fase 1: cadena completa hasta el Lab 05 ====="
if correr bash "$LAB05_95"; then res_f1="OK"; else res_f1="FALLO"; reportar_fallo 1 "Lab 05 95"; limpieza_cluster; finalizar 1 "Fase 1 (cadena Lab 05)"; fi

# Fase 2: scope + DR
echo; msg_info "===== Fase 2: scope del operador + clúster DR ====="
correr kubectl apply --context "$CONTEXTO" -f "$SOL/dr/10-namespace.yaml"
if ! correr helm upgrade strimzi-operator strimzi/strimzi-kafka-operator --version 0.51.0 -n "$NSSIS" --kube-context "$CONTEXTO" --reuse-values --set 'watchNamespaces={meridiano-pagos,meridiano-dr}'; then
  res_f2="FALLO"; reportar_fallo 2 "helm upgrade watchNamespaces"; limpieza_cluster; finalizar 1 "Fase 2 (scope operador)"
fi
correr kubectl rollout status deployment/strimzi-cluster-operator -n "$NSSIS" --context "$CONTEXTO" --timeout=180s
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/dr/20-kafka-dr.yaml"; then res_f2="FALLO"; reportar_fallo 2 "apply dr"; limpieza_cluster; finalizar 1 "Fase 2 (aplicar DR)"; fi
if ! correr kubectl wait --for=condition=Ready kafka/dr -n "$NSD" --context "$CONTEXTO" --timeout=600s; then res_f2="FALLO"; reportar_fallo 2 "wait kafka/dr"; limpieza_cluster; finalizar 1 "Fase 2 (DR no Ready)"; fi
res_f2="OK"; msg_ok "DR Ready."

# Fase 3: mm2 + MM2
echo; msg_info "===== Fase 3: MirrorMaker 2 ====="
correr kubectl apply --context "$CONTEXTO" -f "$SOL/mm2/10-kafkauser-mm2.yaml"
correr kubectl wait --for=condition=Ready kafkauser/mm2 -n "$NSP" --context "$CONTEXTO" --timeout=180s || true
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/mm2/20-mirrormaker2.yaml"; then res_f3="FALLO"; reportar_fallo 3 "apply mm2"; limpieza_cluster; finalizar 1 "Fase 3 (aplicar MM2)"; fi
if ! correr kubectl wait --for=condition=Ready kafkamirrormaker2/pagos-a-dr -n "$NSP" --context "$CONTEXTO" --timeout=600s; then res_f3="FALLO"; reportar_fallo 3 "wait mm2"; limpieza_cluster; finalizar 1 "Fase 3 (MM2 no Ready)"; fi
res_f3="OK"; msg_ok "MM2 Ready."

# Fase 4: métricas + observabilidad
echo; msg_info "===== Fase 4: métricas + Prometheus + Grafana ====="
correr kubectl apply --context "$CONTEXTO" -f "$MET"
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/observabilidad/00-kafka-pagos-metrics.yaml"; then res_f4="FALLO"; reportar_fallo 4 "apply pagos metrics"; limpieza_cluster; finalizar 1 "Fase 4 (metrics)"; fi
if ! correr kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s; then res_f4="FALLO"; reportar_fallo 4 "wait pagos (metrics rolling)"; limpieza_cluster; finalizar 1 "Fase 4 (pagos no Ready)"; fi
if ! correr bash "$DIR_SCRIPT/01-desplegar-observabilidad.sh"; then res_f4="FALLO"; reportar_fallo 4 "01-desplegar-observabilidad"; limpieza_cluster; finalizar 1 "Fase 4 (observabilidad)"; fi
res_f4="OK"; msg_ok "Observabilidad lista."

# Medición del PICO DE MEMORIA (máxima carga: todo desplegado).
mem_total=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1048576}')
mem_uso=$(memoria_docker_mib)
msg_info "[memoria] Pico en máxima carga: ~${mem_uso} MiB de ~${mem_total} MiB totales."

# Fase 5: verificación (90)
echo; msg_info "===== Fase 5: verificación (test 90) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then msg_ok "Verificación superada."
else reportar_fallo 5 "bash bin/90-test-lab.sh"; limpieza_cluster; finalizar 1 "Fase 5 (verificación)"; fi

# Fase 6: limpieza + veredicto
limpieza_cluster
if [ "$res_f5" = "FALLO" ]; then finalizar 1 "Fase 6 (limpieza)"; else finalizar 0 ""; fi
