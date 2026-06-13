#!/usr/bin/env bash
# PLOMERÍA (provista): el DECOMISO. Apaga el espejo de migración y el Kafka
# legado, una vez que la migración está verificada.
#
# Decisión de referencia (justificada): se ELIMINA el KafkaMirrorMaker2 de
# migración (no se deja en spec.state: stopped). Razón: el espejo era temporal,
# cumplió su función; un recurso vivo que replica un origen muerto es deuda
# operativa. La alternativa (spec.state: stopped, conservando el CR) se discute
# en el runbook — válida si se quisiera reanudar; aquí no.
#
# Salvaguarda anti-decomiso-prematuro: se niega a apagar si NO consta el cutover
# (migracion-estado.ultimo-id-legado). Fuérzalo con --forzar bajo tu responsabilidad.
#
# Uso: bin/03-decomisar-legado.sh [--si] [--forzar]
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
MM2="migracion-legado-a-pagos"

CONFIRMAR=0; FORZAR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --si) CONFIRMAR=1; shift ;;
    --forzar) FORZAR=1; shift ;;
    *) msg_error "Parámetro desconocido: $1"; exit 2 ;;
  esac
done

# Salvaguarda: ¿se hizo el cutover?
ULTIMO=$(kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" \
  -o jsonpath='{.data.ultimo-id-legado}' 2>/dev/null || true)
if ! printf '%s' "$ULTIMO" | grep -q '^[0-9]\{1,\}$'; then
  if [ "$FORZAR" -ne 1 ]; then
    msg_error "No consta el cutover (migracion-estado.ultimo-id-legado vacío)."
    msg_error "Decomisar ahora podría perder mensajes aún no replicados. Aborto."
    msg_error "Si sabes lo que haces: vuelve a ejecutar con --forzar."
    exit 1
  fi
  msg_info "Cutover no registrado, pero se fuerza el decomiso (--forzar)."
else
  msg_info "Cutover verificado (último ID del legado = ${ULTIMO})."
fi

msg_info "Esta acción ELIMINA el espejo de migración '${MM2}' y APAGA el Kafka legado."
if [ "$CONFIRMAR" -ne 1 ]; then
  printf '¿Confirmas el decomiso? Escribe "si" para continuar: '
  read -r respuesta
  [ "$respuesta" = "si" ] || { msg_info "Operación cancelada."; exit 0; }
fi

# 1. Eliminar el espejo de migración (cumplió su función).
if kubectl get kafkamirrormaker2 "$MM2" -n "$NSP" --context "$CONTEXTO" >/dev/null 2>&1; then
  kubectl delete kafkamirrormaker2 "$MM2" -n "$NSP" --context "$CONTEXTO" --wait=true --timeout=120s >/dev/null 2>&1 || true
  msg_ok "Espejo de migración '${MM2}' eliminado."
else
  msg_info "El espejo '${MM2}' ya no existe."
fi

# 2. Apagar y eliminar el contenedor del Kafka legado.
if legado_corriendo || [ -n "$(docker ps -aq -f name="^${LEGADO_NOMBRE}$" 2>/dev/null)" ]; then
  docker rm -f "$LEGADO_NOMBRE" >/dev/null 2>&1 || true
  msg_ok "Kafka legado '${LEGADO_NOMBRE}' apagado y eliminado."
else
  msg_info "El Kafka legado '${LEGADO_NOMBRE}' ya estaba apagado."
fi

echo
msg_ok "DECOMISO COMPLETADO. La plataforma 'pagos' es ahora la única fuente del flujo de transferencias."
