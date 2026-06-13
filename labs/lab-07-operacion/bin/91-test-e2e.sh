#!/usr/bin/env bash
# Test end-to-end del Lab 07 (INSTRUCTOR). La corrida FINAL del curso: cadena
# Lab 01->07 con Cruise Control y el ciclo completo de rebalanceo. Mide el pico
# de memoria. LAB07_E2E_CLUSTER=<nombre>; --conservar.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB07_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NSP="meridiano-pagos"
LAB06_95="$DIR_SCRIPT/../../lab-06-contingencia-ojos/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"

CONSERVAR=0; [ "${1:-}" = "--conservar" ] && CONSERVAR=1
LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab07-e2e.XXXXXX")"; trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"
mem_total="?"; mem_uso="?"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() { echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"; msg_error "Últimas líneas:"; tail -n 25 "$LOG_PASO" | sed 's/^/    /'; }
limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f4="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado. Destrúyelo con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"; return 0
  fi
  echo; msg_info "===== Fase 5: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then res_f4="OK"; else res_f4="FALLO"; fi
}
finalizar() {
  fin=$(date +%s); dur=$((fin-INICIO))
  echo; msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s ($((dur/60)) min)"
  msg_info "PICO DE MEMORIA Docker VM en máxima carga: ~${mem_uso} MiB de ~${mem_total} MiB totales"
  msg_info "F0 (guardia): ${res_f0} | F1 (Lab 06): ${res_f1} | F2 (CC): ${res_f2} | F3 (rebalanceo): ${res_f3} | F5 (limpieza): ${res_f4}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el Lab 07 funciona en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}
rebalance() {
  # $1 = nombre, $2 = manifiesto. Reintenta si CC no ve los brokers, espera
  # propuesta, aprueba y espera Ready (robusto frente al refresco de CC).
  msg_info "[rebalance] ${1}: propuesta -> aprobación -> ejecución (Cruise Control necesita su ventana de métricas)..."
  if rebalance_completo "$1" "$2" "$CONTEXTO" "$NSP"; then msg_ok "[rebalance] ${1} completado."; return 0
  else msg_error "[rebalance] ${1} no llegó a Ready."; return 1; fi
}

# Fase 0
msg_info "===== Fase 0: guardia ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"; msg_error "Ya existe '${CLUSTER_E2E}'. Destrúyelo o usa LAB07_E2E_CLUSTER=otro."; finalizar 1 "Fase 0"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo."

# Fase 1: cadena Lab 06
echo; msg_info "===== Fase 1: cadena completa hasta el Lab 06 ====="
if correr bash "$LAB06_95"; then res_f1="OK"; else res_f1="FALLO"; reportar_fallo 1 "Lab 06 95"; limpieza_cluster; finalizar 1 "Fase 1"; fi

# Fase 2: Cruise Control
echo; msg_info "===== Fase 2: encender Cruise Control ====="
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/cruise-control/00-kafka-pagos-cc.yaml"; then res_f2="FALLO"; reportar_fallo 2 "apply CC"; limpieza_cluster; finalizar 1 "Fase 2"; fi
if ! correr kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s; then res_f2="FALLO"; reportar_fallo 2 "wait pagos (CC)"; limpieza_cluster; finalizar 1 "Fase 2"; fi
res_f2="OK"; msg_ok "Cruise Control Ready."

# Fase 3: ciclo de rebalanceo (crecer -> add -> remove -> encoger)
echo; msg_info "===== Fase 3: crecer y rebalancear (add -> remove -> encoger) ====="
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/rebalance/05-nodepool-brokers-4.yaml"; then res_f3="FALLO"; reportar_fallo 3 "scale 4"; limpieza_cluster; finalizar 1 "Fase 3 (escalar a 4)"; fi
if ! correr kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s; then res_f3="FALLO"; reportar_fallo 3 "wait 4 brokers"; limpieza_cluster; finalizar 1 "Fase 3 (4 brokers)"; fi
if ! rebalance agregar-broker-4 "$SOL/rebalance/10-add-brokers.yaml"; then res_f3="FALLO"; reportar_fallo 3 "rebalance add"; limpieza_cluster; finalizar 1 "Fase 3 (add-brokers)"; fi
if ! rebalance vaciar-broker-4 "$SOL/rebalance/20-remove-brokers.yaml"; then res_f3="FALLO"; reportar_fallo 3 "rebalance remove"; limpieza_cluster; finalizar 1 "Fase 3 (remove-brokers)"; fi
if ! correr kubectl apply --context "$CONTEXTO" -f "$SOL/rebalance/25-nodepool-brokers-3.yaml"; then res_f3="FALLO"; reportar_fallo 3 "scale 3"; limpieza_cluster; finalizar 1 "Fase 3 (escalar a 3)"; fi
if ! correr kubectl wait --for=condition=Ready kafka/pagos -n "$NSP" --context "$CONTEXTO" --timeout=600s; then res_f3="FALLO"; reportar_fallo 3 "wait 3 brokers"; limpieza_cluster; finalizar 1 "Fase 3 (3 brokers)"; fi
res_f3="OK"; msg_ok "Ciclo de rebalanceo completado (estado canónico: 3 brokers)."

# Medición de memoria (máxima carga ya pasó en Fase 3 con 4 brokers + CC; mido ahora).
mem_total=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1048576}')
mem_uso=$(memoria_docker_mib)
msg_info "[memoria] ~${mem_uso} MiB de ~${mem_total} MiB."

# Fase 4: verificación
echo; msg_info "===== Fase 4: verificación (test 90) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then msg_ok "Verificación superada."
else reportar_fallo 4 "bash bin/90-test-lab.sh"; limpieza_cluster; finalizar 1 "Fase 4"; fi

# Fase 5: limpieza + veredicto
limpieza_cluster
if [ "$res_f4" = "FALLO" ]; then finalizar 1 "Fase 5 (limpieza)"; else finalizar 0 ""; fi
