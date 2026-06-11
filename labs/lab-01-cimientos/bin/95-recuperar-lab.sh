#!/usr/bin/env bash
# Recuperación del Lab 01: reconstruye el ESTADO FINAL del lab desde cero, sin
# interacción. Útil para un alumno con la VM rota o que perdió una sesión, y
# como pieza de encadenamiento de los e2e de labs futuros.
#
# Se declara exitoso SOLO si el test de estado (90) pasa completo: hereda su
# exit code.
#
# LAB01_CLUSTER permite usar otro nombre de clúster (consistente con el 90).
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

# Se exporta para que los scripts hijos (01, 02, 90) usen el mismo clúster.
export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS_SISTEMA="meridiano-sistema"
VALUES_SOLUCION="$DIR_SCRIPT/../soluciones/values-operador-solucion.yaml"
TIMEOUT_POD="180s"

msg_info "Este script reconstruye el resultado del Lab 01 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

if [ ! -f "$VALUES_SOLUCION" ]; then
  msg_error "No se encontró el archivo de solución: $VALUES_SOLUCION"
  exit 1
fi

# 1. Clúster e infraestructura (reutiliza los scripts del alumno, idempotentes).
bash "$DIR_SCRIPT/01-crear-cluster.sh"
bash "$DIR_SCRIPT/02-crear-namespaces.sh"

# 2. Repositorio Helm de Strimzi (idempotente).
msg_info "Asegurando el repositorio Helm de Strimzi..."
helm repo add strimzi https://strimzi.io/charts/ >/dev/null 2>&1 || true
helm repo update strimzi >/dev/null 2>&1 || true

# 3. Operador: 'helm upgrade --install' es idempotente. Sirve igual si el
#    operador no existe, ya existe, o existe mal configurado: converge al
#    estado final de la solución.
msg_info "Instalando/actualizando el Cluster Operator desde la solución..."
helm upgrade --install strimzi-operator strimzi/strimzi-kafka-operator \
  --version 0.51.0 \
  --namespace "$NS_SISTEMA" \
  --kube-context "$CONTEXTO" \
  --values "$VALUES_SOLUCION"

# 4. Espera activa acotada a que el operador esté disponible.
msg_info "Esperando a que el operador esté disponible (máximo ${TIMEOUT_POD})..."
if kubectl rollout status deployment/strimzi-cluster-operator \
     -n "$NS_SISTEMA" --context "$CONTEXTO" --timeout="$TIMEOUT_POD"; then
  msg_ok "El operador está disponible."
else
  msg_error "El operador no quedó disponible en ${TIMEOUT_POD}."
  msg_error "Revisa 'kubectl get pods -n ${NS_SISTEMA}' y docs/troubleshooting.md."
  exit 1
fi

# 5. Verificación final: la recuperación es exitosa solo si el test 90 pasa.
echo
msg_info "Ejecutando el test de estado (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
