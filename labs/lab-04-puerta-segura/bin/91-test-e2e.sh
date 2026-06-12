#!/usr/bin/env bash
# Test end-to-end del Lab 04 (INSTRUCTOR). Certifica de cero a fin encadenando
# Lab 01 -> 02 -> 03 -> 04, con kcat DESDE EL HOST (lo ejecuta el test 90).
#
# LAB04_E2E_CLUSTER=<nombre> certifica con otro clúster (vía LAB01_CLUSTER).
# Flag --conservar: no destruir al final.
#
# Nota: el clúster del e2e mapea los puertos 32000-32007 al host. No ejecutes dos
# e2e a la vez (chocarían en esos puertos).
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB04_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NS="meridiano-pagos"
CLUSTER="pagos"
LAB03_95="$DIR_SCRIPT/../../lab-03-topicos-identidad/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
TIMEOUT_KAFKA="600s"

CONSERVAR=0
[ "${1:-}" = "--conservar" ] && CONSERVAR=1

LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab04-e2e.XXXXXX")"
trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() {
  echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"
  msg_error "Últimas líneas:"; tail -n 20 "$LOG_PASO" | sed 's/^/    /'
}
limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f4="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado. Destrúyelo con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"
    return 0
  fi
  echo; msg_info "===== Fase 4: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then res_f4="OK"; else res_f4="FALLO"; fi
}
finalizar() {
  fin=$(date +%s); dur=$((fin - INICIO))
  echo; msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s"
  msg_info "Fase 0 (guardia):            ${res_f0}"
  msg_info "Fase 1 (estado Lab 03):      ${res_f1}"
  msg_info "Fase 2 (puerta segura):      ${res_f2}"
  msg_info "Fase 3 (verificación 90):    ${res_f3}"
  msg_info "Fase 4 (limpieza):           ${res_f4}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el Lab 04 funciona en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}

# ===================== Fase 0 =====================
msg_info "===== Fase 0: guardia (certificación desde cero) ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"
  msg_error "Ya existe un clúster '${CLUSTER_E2E}'. Destrúyelo (LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh) o usa LAB04_E2E_CLUSTER=otro."
  res_f4="omitida (clúster preexistente)"
  finalizar 1 "Fase 0 (clúster '${CLUSTER_E2E}' preexistente)"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo. Continuamos."

# ===================== Fase 1: estado del Lab 03 =====================
echo; msg_info "===== Fase 1: estado del Lab 03 ====="
if correr bash "$LAB03_95"; then res_f1="OK"; msg_ok "Estado del Lab 03 reconstruido."
else res_f1="FALLO"; reportar_fallo 1 "bash ../../lab-03-topicos-identidad/bin/95-recuperar-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 1 (estado del Lab 03)"; fi

# ===================== Fase 2: la puerta segura =====================
echo; msg_info "===== Fase 2: la puerta segura (listeners externos + cierre del plano) ====="
if ! correr kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/20-kafka-puerta-segura.yaml"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl apply -f soluciones/20-kafka-puerta-segura.yaml"
  limpieza_cluster; finalizar 1 "Fase 2 (aplicar puerta segura)"
fi
if ! correr kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl wait kafka/${CLUSTER} (tras puerta segura)"
  limpieza_cluster; finalizar 1 "Fase 2 (clúster no Ready)"
fi
if ! correr bash "$DIR_SCRIPT/01-extraer-credenciales.sh"; then
  res_f2="FALLO"; reportar_fallo 2 "bash bin/01-extraer-credenciales.sh"
  limpieza_cluster; finalizar 1 "Fase 2 (extraer credenciales)"
fi
res_f2="OK"; msg_ok "Puerta segura aplicada y credenciales extraídas."

# ===================== Fase 3: verificación (incluye kcat desde el host) =====================
echo; msg_info "===== Fase 3: verificación (test 90, kcat desde el host) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then res_f3="OK"; msg_ok "Verificación superada."
else res_f3="FALLO"; reportar_fallo 3 "bash bin/90-test-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 3 (verificación de estado)"; fi

# ===================== Fase 4: limpieza + veredicto =====================
limpieza_cluster
if [ "$res_f4" = "FALLO" ]; then finalizar 1 "Fase 4 (limpieza)"; else finalizar 0 ""; fi
