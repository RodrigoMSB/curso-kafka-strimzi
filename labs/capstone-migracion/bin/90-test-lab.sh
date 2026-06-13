#!/usr/bin/env bash
# EL EVALUADOR DEL CAPSTONE. Estado final = MIGRACIÓN COMPLETADA. Contrato del
# molde, adaptado: el 90 evalúa el ESTADO FINAL DE LA MIGRACIÓN. Solo lectura.
#
# Veredicto de capstone: "MIGRACIÓN COMPLETADA: cero pérdida verificada" o el
# detalle del criterio fallado.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
TOPICO="$LEGADO_TOPICO"
MM2="migracion-legado-a-pagos"
LAB07_90="$DIR_SCRIPT/../../lab-07-operacion/bin/90-test-lab.sh"

total=0; aprobadas=0
verificar() { total=$((total+1)); if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas+1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi; }

msg_info "Evaluación del Capstone 'La migración' (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

# 1. La plataforma sigue sana: el 90 del Lab 07 en verde (migrar no es romper).
if [ -f "$LAB07_90" ] && bash "$LAB07_90" >/tmp/capstone-lab07-90.out 2>&1; then r=0; else r=1; fi
verificar "Plataforma intacta (el test 90 del Lab 07 en verde)" "$r" \
  "Migrar no debe romper la plataforma. Revisa /tmp/capstone-lab07-90.out o recupera el Lab 07."

# 2. El tópico destino como código: KafkaTopic Ready con RF=3 en pagos.
kt_ready=$(kubectl get kafkatopic "$TOPICO" -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
kt_rf=$(kubectl get kafkatopic "$TOPICO" -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [ "$kt_ready" = "True" ] && [ "$kt_rf" = "3" ]; then r=0; else r=1; fi
verificar "KafkaTopic '${TOPICO}' Ready con RF=3 (heredó la durabilidad de la plataforma) (ready=${kt_ready:-?}, rf=${kt_rf:-?})" "$r" \
  "Declara el tópico como código con replicas: 3 (soluciones/topicos)."

# --- Datos para las verificaciones de paridad y cutover ---
SEMILLA=$(kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.data.semilla}' 2>/dev/null || true)
ULTIMO=$(kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.data.ultimo-id-legado}' 2>/dev/null || true)
printf '%s' "$SEMILLA" | grep -q '^[0-9]\{1,\}$' || SEMILLA=0
IMG=$(imagen_kafka "$NSP" "$CONTEXTO")
PW=$(pw_de_usuario mm2-migracion "$NSP" "$CONTEXTO")

TOTAL=0; OUT=""
if [ -n "$PW" ]; then
  # Snapshot fiel del destino (lectura por partición acotada a offsets: robusta
  # frente al tráfico vivo de la plataforma).
  OUT=$(volcar_destino "$CONTEXTO" "$NSP" "$IMG" mm2-migracion "$PW" "$TOPICO" "par$$")
  TOTAL=$(printf '%s\n' "$OUT" | grep -c '"id":' || true)
  printf '%s' "$TOTAL" | grep -q '^[0-9]\{1,\}$' || TOTAL=0
fi

# Análisis de la serie de IDs (global, legado y plataforma).
set -- $(printf '%s\n' "$OUT" | analizar_ids);                              gmin=$1; gmax=$2; gdist=$3; gesp=$4
set -- $(printf '%s\n' "$OUT" | grep '"origen":"legado"'     | analizar_ids); lmin=$1; lmax=$2; ldist=$3; lesp=$4
set -- $(printf '%s\n' "$OUT" | grep '"origen":"plataforma"' | analizar_ids); pmin=$1; pmax=$2; pdist=$3; pesp=$4
plat_count=$(printf '%s\n' "$OUT" | grep -c '"origen":"plataforma"' || true)

# 3. Paridad SIN pérdida: total en destino >= semilla y serie CONTINUA (sin huecos).
if [ "$TOTAL" -ge "$SEMILLA" ] && [ "$SEMILLA" -gt 0 ] && [ "$gmin" -eq 1 ] && [ "$gdist" -eq "$gesp" ] && [ "$gdist" -ge "$SEMILLA" ]; then r=0; else r=1; fi
verificar "Paridad sin pérdida: ${TOTAL} en destino >= ${SEMILLA} semilla; serie continua IDs ${gmin}..${gmax} (${gdist} distintos, esperados ${gesp})" "$r" \
  "Conteo insuficiente o hueco en la serie. Revisa el MM2 (auth del target) y deja drenar antes de evaluar."

# 4. Cutover limpio: hay mensajes de la identidad NUEVA después del último ID del
#    legado, y la frontera calza exactamente (legado=último, plataforma=último+1).
ULTIMO_OK=0; printf '%s' "$ULTIMO" | grep -q '^[0-9]\{1,\}$' && ULTIMO_OK=1
if [ "$ULTIMO_OK" -eq 1 ] && [ "$plat_count" -ge 1 ] && [ "$lmax" -eq "$ULTIMO" ] && [ "$pmin" -eq "$((ULTIMO + 1))" ]; then r=0; else r=1; fi
verificar "Cutover limpio: legado hasta ID ${lmax} (marca=${ULTIMO:-?}), plataforma desde ID ${pmin} (${plat_count} msgs nuevos), sin hueco ni duplicado en la frontera" "$r" \
  "El primer ID de la plataforma debe ser último-del-legado + 1. Revisa 02-cutover y la marca migracion-estado."

# 5. Decomiso: el legado apagado (contenedor ausente) y el espejo de migración no activo.
legado_ausente=1; { legado_corriendo || [ -n "$(docker ps -aq -f name="^${LEGADO_NOMBRE}$" 2>/dev/null)" ]; } && legado_ausente=0
mm2_obj=$(kubectl get kafkamirrormaker2 "$MM2" -n "$NSP" --context "$CONTEXTO" -o name 2>/dev/null || true)
mm2_state=$(kubectl get kafkamirrormaker2 "$MM2" -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.spec.state}' 2>/dev/null || true)
mm2_inactivo=0; { [ -z "$mm2_obj" ] || [ "$mm2_state" = "stopped" ]; } && mm2_inactivo=1
if [ "$legado_ausente" -eq 1 ] && [ "$mm2_inactivo" -eq 1 ]; then r=0; else r=1; fi
verificar "Decomiso: Kafka legado apagado y espejo de migración no activo (legado_ausente=${legado_ausente}, mm2=${mm2_obj:-ausente}${mm2_state:+/$mm2_state})" "$r" \
  "Ejecuta 03-decomisar-legado.sh: elimina/para el MM2 de migración y apaga el contenedor legado."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} criterios superados"
  msg_ok "MIGRACIÓN COMPLETADA: cero pérdida verificada"
  exit 0
else
  msg_error "${aprobadas}/${total} criterios superados"
  msg_error "MIGRACIÓN INCOMPLETA: revisa el criterio fallado arriba"
  exit 1
fi
