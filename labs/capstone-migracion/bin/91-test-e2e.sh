#!/usr/bin/env bash
# Test end-to-end del Capstone (INSTRUCTOR). La corrida TOTAL del curso: cadena
# Lab 01->07 (vía el 95 del Lab 07) + la migración completa, de cero a fin. Mide
# duración y pico de memoria. CAPSTONE_E2E_CLUSTER=<nombre>; --conservar.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"
LAB07_DIR="$DIR_SCRIPT/../../lab-07-operacion"
. "$LAB07_DIR/bin/lib-comunes.sh"   # aporta rebalance_completo para el fallback de CC.

CLUSTER_E2E="${CAPSTONE_E2E_CLUSTER:-meridiano}"
export LAB01_CLUSTER="$CLUSTER_E2E"
CONTEXTO="kind-${CLUSTER_E2E}"
NSP="meridiano-pagos"
SOL="$DIR_SCRIPT/../soluciones"
LAB07_95="$LAB07_DIR/bin/95-recuperar-lab.sh"

# Fallback de robustez para la conocida fragilidad del rebalanceo de Cruise
# Control del Lab 07: su primera propuesta depende de la ventana de métricas de
# CC y, si CC se reinicia a mitad, el rebalance queda NotReady. Reintentar el 95
# COMPLETO es contraproducente (vuelve a hacer rolling de CC -> CC frío otra vez).
# Este fallback COMPLETA la plataforma sobre el CC ya CALIENTE, sin reiniciarlo.
completar_plataforma_lab07() {
  s="$LAB07_DIR/soluciones/rebalance"
  kubectl --context "$CONTEXTO" -n "$NSP" wait --for=condition=Ready kafka/pagos --timeout=300s || return 1
  kubectl --context "$CONTEXTO" -n "$NSP" delete kafkarebalance agregar-broker-4 vaciar-broker-4 --ignore-not-found >/dev/null 2>&1
  # Reafirmar Cruise Control habilitado y ESPERAR a que su pod esté Running (sin
  # CC vivo el rebalance queda NotReady para siempre; bajo la carga del build CC
  # puede tardar en agendarse).
  kubectl --context "$CONTEXTO" apply -f "$LAB07_DIR/soluciones/cruise-control/00-kafka-pagos-cc.yaml" >/dev/null
  kubectl --context "$CONTEXTO" apply -f "$s/05-nodepool-brokers-4.yaml" >/dev/null
  kubectl --context "$CONTEXTO" -n "$NSP" wait --for=condition=Ready kafka/pagos --timeout=600s || return 1
  msg_info "[fallback CC] esperando a que el pod de Cruise Control esté Running..."
  ccup=0
  for i in $(seq 1 40); do
    if [ "$(kubectl --context "$CONTEXTO" -n "$NSP" get pods 2>/dev/null | grep cruise | grep -c Running)" -ge 1 ]; then ccup=1; break; fi
    sleep 15
  done
  if [ "$ccup" -ne 1 ]; then
    msg_error "[fallback CC] Cruise Control no llegó a Running. Diagnóstico:"
    kubectl --context "$CONTEXTO" -n "$NSP" get pods | grep -i 'cruise\|NAME' || true
    kubectl --context "$CONTEXTO" -n "$NSP" describe pod -l strimzi.io/name=pagos-cruise-control 2>/dev/null | grep -A6 'Events:\|Conditions:' | head -20 || true
    return 1
  fi
  msg_ok "[fallback CC] Cruise Control Running."
  # Bajo la carga del build, CC tarda en acumular su ventana de métricas para el
  # broker 4 recién añadido. La secuencia es válida (probada en frío); solo
  # necesita que CC asiente. Reintentamos el add con ventanas amplias.
  ok=1
  for intento in 1 2 3 4 5; do
    kubectl --context "$CONTEXTO" -n "$NSP" delete kafkarebalance agregar-broker-4 --ignore-not-found >/dev/null 2>&1
    msg_info "[fallback CC] estado CC: $(kubectl --context "$CONTEXTO" -n "$NSP" get pods 2>/dev/null | grep cruise | awk '{print $1, $2, $3, "restarts="$4}')"
    msg_info "[fallback CC] esperando ventana de métricas de Cruise Control (180s, intento ${intento}/5)..."
    sleep 180
    if rebalance_completo agregar-broker-4 "$s/10-add-brokers.yaml" "$CONTEXTO" "$NSP"; then ok=0; break; fi
    msg_info "[fallback CC] CC aún no propone; reintento."
  done
  [ "$ok" -eq 0 ] || { msg_error "[fallback CC] Cruise Control no logró proponer el rebalanceo tras 5 ventanas."; return 1; }
  rebalance_completo vaciar-broker-4 "$s/20-remove-brokers.yaml" "$CONTEXTO" "$NSP" || return 1
  kubectl --context "$CONTEXTO" apply -f "$s/25-nodepool-brokers-3.yaml" >/dev/null
  kubectl --context "$CONTEXTO" -n "$NSP" wait --for=condition=Ready kafka/pagos --timeout=600s || return 1
  # Verificación final con reintentos: bajo carga, algunos checks del Lab 06
  # (round-trip de réplica, observabilidad) pueden fallar de forma transitoria.
  for v in 1 2 3 4; do
    if bash "$LAB07_DIR/bin/90-test-lab.sh" >/tmp/capstone-fallback-lab07-90.out 2>&1; then return 0; fi
    msg_info "[fallback CC] verificación del Lab 07 transitoria (intento ${v}/4); reintento en 30s..."
    sleep 30
  done
  msg_error "[fallback CC] el test 90 del Lab 07 no quedó verde. Detalle:"
  grep -E '\[ERROR\]' /tmp/capstone-fallback-lab07-90.out | head -8
  return 1
}

CONSERVAR=0; [ "${1:-}" = "--conservar" ] && CONSERVAR=1
LOG_PASO="$(mktemp "${TMPDIR:-/tmp}/capstone-e2e.XXXXXX")"
MEMFILE="$(mktemp "${TMPDIR:-/tmp}/capstone-mem.XXXXXX")"; echo 0 > "$MEMFILE"
trap 'rm -f "$LOG_PASO" "$MEMFILE"' EXIT
INICIO=$(date +%s)
res_f0="-"; res_f1="-"; res_f2="-"; res_f3="-"; res_f4="-"
mem_total="?"; mem_uso="?"
num_semilla="?"; num_ultimo="?"; num_destino="?"

correr() { msg_info ">>> Comando: $*"; "$@" 2>&1 | tee "$LOG_PASO"; return "${PIPESTATUS[0]}"; }
reportar_fallo() { echo; msg_error "FALLO en Fase $1."; msg_error "Comando: $2"; msg_error "Últimas líneas:"; tail -n 25 "$LOG_PASO" | sed 's/^/    /'; }

# Muestreador de memoria en segundo plano: guarda el máximo observado.
( max=0; while :; do
    m=$(memoria_docker_mib)
    case "$m" in ''|*[!0-9]*) : ;; *) if [ "$m" -gt "$max" ]; then max=$m; echo "$max" > "$MEMFILE"; fi ;; esac
    sleep 15
  done ) &
SAMPLER=$!
detener_sampler() { kill "$SAMPLER" >/dev/null 2>&1 || true; }

limpieza_cluster() {
  if [ "$CONSERVAR" -eq 1 ]; then
    res_f4="conservado (--conservar)"
    msg_info "Clúster '${CLUSTER_E2E}' conservado. Destrúyelo con: LAB01_CLUSTER=${CLUSTER_E2E} bash bin/99-destruir-lab.sh --si"; return 0
  fi
  echo; msg_info "===== Fase 4: limpieza ====="
  if bash "$DIR_SCRIPT/99-destruir-lab.sh" --si; then res_f4="OK"; else res_f4="FALLO"; fi
}
finalizar() {
  detener_sampler
  fin=$(date +%s); dur=$((fin-INICIO))
  [ "$mem_uso" = "?" ] && mem_uso=$(cat "$MEMFILE" 2>/dev/null); [ -z "$mem_uso" ] && mem_uso="?"
  [ "$mem_total" = "?" ] && mem_total=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1048576}')
  echo; msg_info "===== Resumen del e2e (clúster '${CLUSTER_E2E}') ====="
  msg_info "Duración total: ${dur}s ($((dur/60)) min)"
  msg_info "PICO DE MEMORIA Docker VM: ~${mem_uso} MiB de ~${mem_total} MiB totales"
  msg_info "Números de la migración: semilla=${num_semilla}, último ID legado=${num_ultimo}, total en destino=${num_destino}"
  msg_info "F0 (guardia): ${res_f0} | F1 (plataforma 01-07): ${res_f1} | F2 (migración): ${res_f2} | F3 (evaluación): ${res_f3} | F4 (limpieza): ${res_f4}"
  echo
  if [ "$1" -eq 0 ]; then msg_ok "E2E APROBADO: el curso completo + la migración funcionan en este ambiente."
  else msg_error "E2E FALLIDO en ${2}."; fi
  exit "$1"
}

# Fase 0: guardia.
msg_info "===== Fase 0: guardia ====="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_E2E}$"; then
  res_f0="FALLO"; msg_error "Ya existe '${CLUSTER_E2E}'. Destrúyelo o usa CAPSTONE_E2E_CLUSTER=otro."; finalizar 1 "Fase 0"
fi
res_f0="OK"; msg_ok "No existe '${CLUSTER_E2E}' previo."

# Fase 1: plataforma completa (cadena del curso vía el 95 del Lab 07).
# Si el 95 cae en el rebalanceo de CC (flaky por su ventana de métricas), se
# completa la plataforma sobre el CC ya caliente, sin reiniciarlo (fallback).
echo; msg_info "===== Fase 1: plataforma completa (Lab 01->07) ====="
res_f1="FALLO"
if correr bash "$LAB07_95"; then
  res_f1="OK"
else
  msg_info "Fase 1: el 95 del Lab 07 no cerró (rebalanceo de Cruise Control). Aplicando fallback sobre CC caliente..."
  if correr completar_plataforma_lab07; then res_f1="OK"; fi
fi
if [ "$res_f1" != "OK" ]; then reportar_fallo 1 "Lab 07 95 + fallback CC"; limpieza_cluster; finalizar 1 "Fase 1"; fi

# Fase 2: la migración de punta a punta (solución de referencia).
echo; msg_info "===== Fase 2: la migración (legado -> plataforma) ====="
if correr ejecutar_migracion "$CONTEXTO" "$NSP" "$SOL" "$DIR_SCRIPT"; then res_f2="OK"; else res_f2="FALLO"; reportar_fallo 2 "ejecutar_migracion"; limpieza_cluster; finalizar 1 "Fase 2"; fi

# Números de la migración (para el informe).
num_semilla=$(kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.data.semilla}' 2>/dev/null || echo "?")
num_ultimo=$(kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.data.ultimo-id-legado}' 2>/dev/null || echo "?")
PW=$(pw_de_usuario mm2-migracion "$NSP" "$CONTEXTO")
IMG=$(imagen_kafka "$NSP" "$CONTEXTO")
[ -n "$PW" ] && num_destino=$(contar_destino "$CONTEXTO" "$NSP" "$IMG" mm2-migracion "$PW" "$LEGADO_TOPICO" "rep$$")

# Pico de memoria observado por el muestreador.
mem_total=$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1048576}')
mem_uso=$(cat "$MEMFILE" 2>/dev/null); [ -z "$mem_uso" ] && mem_uso="?"
detener_sampler

# Fase 3: evaluación (test 90). Reintentos para absorber checks transitorios del
# Lab 06 (round-trip/observabilidad) heredados por el check 1 del capstone.
echo; msg_info "===== Fase 3: evaluación (test 90) ====="
res_f3="FALLO"
for v in 1 2 3; do
  if correr bash "$DIR_SCRIPT/90-test-lab.sh"; then res_f3="OK"; break; fi
  [ "$v" -lt 3 ] && { msg_info "Fase 3: evaluación transitoria (intento ${v}/3); reintento en 30s..."; sleep 30; }
done
if [ "$res_f3" = "OK" ]; then msg_ok "Evaluación superada."
else reportar_fallo 3 "bash bin/90-test-lab.sh"; limpieza_cluster; finalizar 1 "Fase 3"; fi

# Fase 4: limpieza + veredicto.
limpieza_cluster
if [ "$res_f4" = "FALLO" ]; then finalizar 1 "Fase 4 (limpieza)"; else finalizar 0 ""; fi
