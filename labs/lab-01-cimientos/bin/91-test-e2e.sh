#!/usr/bin/env bash
# Test end-to-end del Lab 01 (herramienta del INSTRUCTOR). Certifica, de cero a
# fin y sin intervención manual, que el lab completo funciona en un ambiente
# dado (VM Windows/WSL2 de Netec, un Mac nuevo, etc.) en una sola corrida.
#
# Por defecto opera sobre un clúster llamado 'meridiano' y, para no certificar
# encima de un entorno de trabajo real, la Fase 0 aborta si ya existe.
#
# LAB01_E2E_CLUSTER=<nombre> certifica con OTRO nombre de clúster sin chocar con
# tu entorno. Ese nombre se propaga a los scripts del lab mediante la variable
# LAB01_CLUSTER, soportada por 00..02, 90 y 99.
#
# Flags:
#   --conservar   no destruir el clúster del e2e al final (para inspeccionar una falla).
#
# No se usa 'set -e': el script controla las fallas para poder limpiar y emitir
# un veredicto único.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

CLUSTER_E2E="${LAB01_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"   # los scripts del lab heredan este nombre
CONTEXTO="kind-${CLUSTER_E2E}"
NS_SISTEMA="meridiano-sistema"
VALUES_SOLUCION="$DIR_SCRIPT/../soluciones/values-operador-solucion.yaml"
TIMEOUT_POD="180s"

CONSERVAR=0
if [ "${1:-}" = "--conservar" ]; then
  CONSERVAR=1
fi

LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/lab01-e2e.XXXXXX")"
trap 'rm -f "$LOG_PASO"' EXIT

INICIO=$(date +%s)

# Resultados por fase (para el resumen final).
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"

# Ejecuta un comando mostrando su salida en vivo y deja una copia en LOG_PASO
# para poder reproducir las últimas líneas si falla. Devuelve el exit del comando.
correr() {
  msg_info ">>> Comando: $*"
  "$@" 2>&1 | tee "$LOG_PASO"
  return "${PIPESTATUS[0]}"
}

# Reporte autosuficiente de una falla (lo que el instructor pega para diagnóstico).
reportar_fallo() {
  # $1 = número de fase, $2 = comando exacto que falló
  echo
  msg_error "FALLO en Fase $1."
  msg_error "Comando que falló: $2"
  msg_error "Últimas líneas de su salida:"
  tail -n 20 "$LOG_PASO" | sed 's/^/    /'
}

# Limpieza del clúster del e2e (Fase 4). Respeta --conservar.
limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f4="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado por --conservar."
    msg_info "Destrúyelo luego con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"
    return 0
  fi
  echo
  msg_info "===== Fase 4: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then
    res_f4="OK"
  else
    res_f4="FALLO"
  fi
}

# Imprime el resumen y termina con el código indicado.
finalizar() {
  # $1 = exit code, $2 = veredicto de falla (vacío si éxito)
  fin=$(date +%s)
  dur=$((fin - INICIO))
  echo
  msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s"
  msg_info "Fase 0 (guardia):        ${res_f0}"
  msg_info "Fase 1 (entorno):        ${res_f1}"
  msg_info "Fase 2 (ejecución lab):  ${res_f2}"
  msg_info "Fase 3 (verificación):   ${res_f3}"
  msg_info "Fase 4 (limpieza):       ${res_f4}"
  echo
  if [ "$1" -eq 0 ]; then
    msg_ok "E2E APROBADO: el Lab 01 funciona en este ambiente."
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
  msg_error "El e2e certifica DESDE CERO y no debe convivir con un entorno real."
  msg_error "Destrúyelo primero con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh"
  msg_error "O certifica con otro nombre: LAB01_E2E_CLUSTER=otro bash bin/91-test-e2e.sh"
  res_f4="omitida (clúster preexistente, no se toca)"
  finalizar 1 "Fase 0 (clúster '${CLUSTER_E2E}' preexistente)"
fi
res_f0="OK"
msg_ok "No existe un clúster '${CLUSTER_E2E}' previo. Continuamos."

# ===================== Fase 1: verificación de entorno =====================
echo
msg_info "===== Fase 1: verificación de entorno ====="
if correr bash "$DIR_SCRIPT/00-verificar-entorno.sh"; then
  res_f1="OK"; msg_ok "Entorno verificado."
else
  res_f1="FALLO"
  reportar_fallo 1 "bash bin/00-verificar-entorno.sh"
  res_f4="omitida (no se creó clúster)"
  finalizar 1 "Fase 1 (verificación de entorno)"
fi

# ===================== Fase 2: ejecución del lab =====================
echo
msg_info "===== Fase 2: ejecución del lab ====="

if ! correr bash "$DIR_SCRIPT/01-crear-cluster.sh"; then
  res_f2="FALLO"; reportar_fallo 2 "bash bin/01-crear-cluster.sh"
  limpieza_cluster; finalizar 1 "Fase 2 (creación del clúster)"
fi

if ! correr bash "$DIR_SCRIPT/02-crear-namespaces.sh"; then
  res_f2="FALLO"; reportar_fallo 2 "bash bin/02-crear-namespaces.sh"
  limpieza_cluster; finalizar 1 "Fase 2 (creación de namespaces)"
fi

# Repositorio Helm (camino del alumno, idempotente).
helm repo add strimzi https://strimzi.io/charts/ >/dev/null 2>&1 || true
helm repo update strimzi >/dev/null 2>&1 || true

# Instalación del operador con 'helm install' (cluster recién nacido) usando la
# plantilla resuelta de soluciones/.
if ! correr helm install strimzi-operator strimzi/strimzi-kafka-operator \
       --version 0.51.0 \
       --namespace "$NS_SISTEMA" \
       --kube-context "$CONTEXTO" \
       --values "$VALUES_SOLUCION"; then
  res_f2="FALLO"; reportar_fallo 2 "helm install strimzi-operator strimzi/strimzi-kafka-operator --version 0.51.0 --namespace ${NS_SISTEMA}"
  limpieza_cluster; finalizar 1 "Fase 2 (instalación del operador)"
fi

# Espera al operador (igual que el 95).
if ! correr kubectl rollout status deployment/strimzi-cluster-operator \
       -n "$NS_SISTEMA" --context "$CONTEXTO" --timeout="$TIMEOUT_POD"; then
  res_f2="FALLO"; reportar_fallo 2 "kubectl rollout status deployment/strimzi-cluster-operator -n ${NS_SISTEMA}"
  limpieza_cluster; finalizar 1 "Fase 2 (operador no disponible a tiempo)"
fi
res_f2="OK"; msg_ok "Lab ejecutado; operador disponible."

# ===================== Fase 3: verificación =====================
echo
msg_info "===== Fase 3: verificación (batería del test 90) ====="
if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then
  res_f3="OK"; msg_ok "Verificación completa superada."
else
  res_f3="FALLO"; reportar_fallo 3 "bash bin/90-test-lab.sh"
  limpieza_cluster; finalizar 1 "Fase 3 (verificación de estado)"
fi

# ===================== Fase 4: limpieza + veredicto =====================
limpieza_cluster
if [ "$res_f4" = "FALLO" ]; then
  finalizar 1 "Fase 4 (limpieza)"
else
  finalizar 0 ""
fi
