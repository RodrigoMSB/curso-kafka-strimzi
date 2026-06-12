#!/usr/bin/env bash
# Test end-to-end del Lab 02 (herramienta del INSTRUCTOR). Certifica de cero a
# fin: estado del Lab 01 -> despliegue del Lab 02 desde soluciones -> test 90 ->
# limpieza. Sin intervención manual.
#
# Por defecto opera sobre el clúster 'meridiano' y la Fase 0 aborta si ya existe
# (no se certifica encima de un entorno real). LAB02_E2E_CLUSTER=<nombre>
# certifica con otro nombre de clúster; se propaga vía LAB01_CLUSTER.
#
# Flags: --conservar  no destruir el clúster del e2e al final.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB02_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NS="meridiano-pagos"
CLUSTER="pagos"
BOOTSTRAP="pagos-kafka-bootstrap:9092"
TOPICO="pagos.meridiano.transacciones"
LAB01_95="$DIR_SCRIPT/../../lab-01-cimientos/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones/parte-2-persistente"
TIMEOUT_KAFKA="600s"

CONSERVAR=0
[ "${1:-}" = "--conservar" ] && CONSERVAR=1

LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab02-e2e.XXXXXX")"
trap 'rm -f "$LOG_PASO"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"

correr() {
  msg_info ">>> Comando: $*"
  "$@" 2>&1 | tee "$LOG_PASO"
  return "${PIPESTATUS[0]}"
}
reportar_fallo() {
  echo
  msg_error "FALLO en Fase $1."
  msg_error "Comando que falló: $2"
  msg_error "Últimas líneas de su salida:"
  tail -n 20 "$LOG_PASO" | sed 's/^/    /'
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
  echo
  msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s"
  msg_info "Fase 0 (guardia):              ${res_f0}"
  msg_info "Fase 1 (estado Lab 01):        ${res_f1}"
  msg_info "Fase 2 (despliegue Lab 02):    ${res_f2}"
  msg_info "Fase 3 (verificación 90):      ${res_f3}"
  msg_info "Fase 4 (limpieza):             ${res_f4}"
  echo
  if [ "$1" -eq 0 ]; then
    msg_ok "E2E APROBADO: el Lab 02 funciona en este ambiente."
  else
    msg_error "E2E FALLIDO en ${2}."
  fi
  exit "$1"
}

# ===================== Fase 0: guardia =====================
msg_info "===== Fase 0: guardia (certificación desde cero) ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"
  msg_error "Ya existe un clúster kind '${CLUSTER_E2E}'."
  msg_error "El e2e certifica DESDE CERO. Destrúyelo primero (LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh)"
  msg_error "o certifica con otro nombre: LAB02_E2E_CLUSTER=otro bash bin/91-test-e2e.sh"
  res_f4="omitida (clúster preexistente, no se toca)"
  finalizar 1 "Fase 0 (clúster '${CLUSTER_E2E}' preexistente)"
fi
res_f0="OK"; msg_ok "No existe un clúster '${CLUSTER_E2E}' previo. Continuamos."

# ===================== Fase 1: estado del Lab 01 =====================
echo; msg_info "===== Fase 1: estado del Lab 01 (clúster + operador) ====="
if correr bash "$LAB01_95"; then
  res_f1="OK"; msg_ok "Estado del Lab 01 reconstruido."
else
  res_f1="FALLO"; reportar_fallo 1 "bash ../../lab-01-cimientos/bin/95-recuperar-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 1 (estado del Lab 01)"
fi

# ===================== Fase 2: despliegue del Lab 02 =====================
echo; msg_info "===== Fase 2: despliegue del Lab 02 (persistente + rack) ====="

if ! correr bash "$DIR_SCRIPT/01-etiquetar-zonas.sh"; then
  res_f2="FALLO"; reportar_fallo 2 "bash bin/01-etiquetar-zonas.sh"
  limpieza_cluster; finalizar 1 "Fase 2 (etiquetado de zonas)"
fi

if ! correr kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl apply -n ${NS} -f soluciones/parte-2-persistente"
  limpieza_cluster; finalizar 1 "Fase 2 (aplicar manifiestos)"
fi

if ! correr kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl wait --for=condition=Ready kafka/${CLUSTER} -n ${NS}"
  limpieza_cluster; finalizar 1 "Fase 2 (clúster Kafka no llegó a Ready)"
fi

IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"
if ! correr kubectl run "cli-topic-e2e-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
       --image="$IMG" --command -- bin/kafka-topics.sh \
       --bootstrap-server "$BOOTSTRAP" --create --if-not-exists \
       --topic "$TOPICO" --partitions 3 --replication-factor 3 \
       --config min.insync.replicas=2; then
  res_f2="FALLO"; reportar_fallo 2 "kafka-topics.sh --create ${TOPICO}"
  limpieza_cluster; finalizar 1 "Fase 2 (creación del tópico)"
fi
res_f2="OK"; msg_ok "Lab 02 desplegado."

# ===================== Fase 3: verificación =====================
echo; msg_info "===== Fase 3: verificación (test 90 del Lab 02) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then
  res_f3="OK"; msg_ok "Verificación completa superada."
else
  res_f3="FALLO"; reportar_fallo 3 "bash bin/90-test-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 3 (verificación de estado)"
fi

# ===================== Fase 4: limpieza + veredicto =====================
limpieza_cluster
if [ "$res_f4" = "FALLO" ]; then finalizar 1 "Fase 4 (limpieza)"; else finalizar 0 ""; fi
