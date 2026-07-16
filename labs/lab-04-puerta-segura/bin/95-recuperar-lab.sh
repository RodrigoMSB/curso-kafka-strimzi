#!/usr/bin/env bash
# Recuperación del Lab 04: reconstruye el ESTADO FINAL (dos listeners externos,
# puerta plana cerrada, credenciales extraídas) sin interacción. Encadena el 95
# del Lab 03 y hereda el exit code del test 90 del Lab 04.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

export LAB01_CLUSTER="${LAB01_CLUSTER:-meridiano}"
NOMBRE_CLUSTER="$LAB01_CLUSTER"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
LAB03_95="$DIR_SCRIPT/../../lab-03-topicos-identidad/bin/95-recuperar-lab.sh"
SOL="$DIR_SCRIPT/../soluciones"
TIMEOUT_KAFKA="600s"

msg_info "Este script reconstruye el resultado del Lab 04 sin pasar por las guías."
msg_info "Úsalo solo para ponerte al día; el aprendizaje está en las guías."
echo

# 1. Estado final del Lab 03 (clúster endurecido, usuarios, tópicos).
msg_info "Reconstruyendo primero el estado del Lab 03..."
if ! bash "$LAB03_95" >/tmp/lab04-lab03-95.out 2>&1; then
  msg_error "La recuperación del Lab 03 falló. Detalle:"
  tail -n 15 /tmp/lab04-lab03-95.out | sed 's/^/    /'
  exit 1
fi
msg_ok "Estado del Lab 03 reconstruido."

# 2. Aplicar el CR de la puerta segura (añade listeners externos, quita el plano).
msg_info "Aplicando la puerta segura (listeners externos + cierre del plano)..."
kubectl apply -n "$NS" --context "$CONTEXTO" -f "$SOL/parte-2-sin-plano/20-kafka-puerta-segura.yaml"
msg_info "Esperando a que el clúster vuelva a Ready tras el rolling (máximo ${TIMEOUT_KAFKA})..."
if ! kubectl wait --for=condition=Ready "kafka/${CLUSTER}" -n "$NS" --context "$CONTEXTO" --timeout="$TIMEOUT_KAFKA"; then
  msg_error "El clúster no volvió a Ready. Revisa 'kubectl get pods -n ${NS}'."
  exit 1
fi

# 3. Extraer credenciales para el acceso externo.
bash "$DIR_SCRIPT/01-extraer-credenciales.sh"

# 4. Verificación final: hereda el exit code del test 90 del Lab 04.
echo
msg_info "Ejecutando el test de estado del Lab 04 (bin/90-test-lab.sh)..."
echo
exec bash "$DIR_SCRIPT/90-test-lab.sh"
