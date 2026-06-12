#!/usr/bin/env bash
# Verifica el prerrequisito del Lab 03: el estado final del Lab 02 (clúster de
# pagos persistente con rack y el tópico de transacciones) está presente.
# Se ejecuta ANTES del endurecimiento, así que el listener plano aún funciona y
# el test 90 del Lab 02 debe estar en verde.
#
# LAB01_CLUSTER permite apuntar a otro clúster.
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

LAB02_90="$DIR_SCRIPT/../../lab-02-cluster-pagos/bin/90-test-lab.sh"

msg_info "Verificando el prerrequisito del Lab 03 (estado final del Lab 02)..."
echo

if [ ! -f "$LAB02_90" ]; then
  msg_error "No se encontró el test 90 del Lab 02 en: $LAB02_90"
  exit 1
fi

if bash "$LAB02_90"; then
  echo
  msg_ok "Prerrequisito satisfecho. Puedes empezar el Lab 03."
else
  echo
  msg_error "El Lab 02 no está completo. Recupéralo con:"
  msg_error "  labs/lab-02-cluster-pagos/bin/95-recuperar-lab.sh"
  exit 1
fi
