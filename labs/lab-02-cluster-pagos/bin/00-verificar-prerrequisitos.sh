#!/usr/bin/env bash
# Verifica los prerrequisitos del Lab 02 (no instala nada):
#   - El estado final del Lab 01 está presente (reutiliza su test 90).
#   - El clúster tiene la topología de 4 nodos del curso (1 control-plane + 3 workers).
#
# LAB01_CLUSTER permite apuntar a otro clúster (lo usan 90/91/95).
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
LAB01_90="$DIR_SCRIPT/../../lab-01-cimientos/bin/90-test-lab.sh"

errores=0

msg_info "Verificando prerrequisitos del Lab 02 sobre el clúster '${NOMBRE_CLUSTER}'..."
echo

# 1. Estado final del Lab 01 (operador instalado y vigilando).
if [ -f "$LAB01_90" ]; then
  msg_info "Ejecutando el test del Lab 01 (90)..."
  if bash "$LAB01_90" >/tmp/lab01-90.out 2>&1; then
    msg_ok "El estado final del Lab 01 está presente (test 90 en verde)."
  else
    msg_error "El Lab 01 no está completo. Ejecuta su recuperación: labs/lab-01-cimientos/bin/95-recuperar-lab.sh"
    msg_error "Detalle (últimas líneas del test 90 del Lab 01):"
    tail -n 5 /tmp/lab01-90.out | sed 's/^/    /'
    errores=$((errores + 1))
  fi
else
  msg_error "No se encontró el test 90 del Lab 01 en: $LAB01_90"
  errores=$((errores + 1))
fi

# 2. Topología de 4 nodos.
nodos=$(kubectl get nodes --context "$CONTEXTO" -o name 2>/dev/null | grep -c . || true)
if [ "$nodos" -ge 4 ]; then
  msg_ok "El clúster tiene ${nodos} nodos (se requieren 4: 1 control-plane + 3 workers)."
else
  msg_error "El clúster tiene ${nodos} nodo(s); el Lab 02 requiere 4 (1 control-plane + 3 workers)."
  msg_error "El instructor debe recrear el clúster con la topología del curso (99 + 95 del Lab 01)."
  errores=$((errores + 1))
fi

echo
if [ "$errores" -eq 0 ]; then
  msg_ok "Prerrequisitos satisfechos. Puedes empezar el Lab 02."
else
  msg_error "Prerrequisitos NO satisfechos (${errores}). Resuélvelos antes de continuar."
  exit 1
fi
