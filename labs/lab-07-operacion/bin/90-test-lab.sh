#!/usr/bin/env bash
# Test de estado del Lab 07 (operación). Contrato del molde.
# Estado final canónico: Cruise Control en pagos, historia de rebalanceo (add y
# remove en Ready), pool de brokers en 3, DR en 4.2.0, MM2 replicando.
#
# Nota (de-risk sección 3): NO se verifica Drain Cleaner. El de-risk demostró que
# en kind los PV locales dejan los brokers de pagos caídos al drenar (indemostrable
# dignamente), así que la guía 07 es conceptual + referencia, sin instalación viva.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"; NSD="meridiano-dr"
LAB06_90="$DIR_SCRIPT/../../lab-06-contingencia-ojos/bin/90-test-lab.sh"

total=0; aprobadas=0
verificar() { total=$((total+1)); if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas+1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi; }

msg_info "Test del Lab 07 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

# 1. Estado del Lab 06 (DR + MM2 + observabilidad) intacto.
if [ -f "$LAB06_90" ] && bash "$LAB06_90" >/tmp/lab07-lab06-90.out 2>&1; then r=0; else r=1; fi
verificar "Estado del Lab 06 intacto (su test 90 en verde)" "$r" "Recupera con bin/95-recuperar-lab.sh"

# 2. Cruise Control desplegado y Ready en pagos.
cc=$(kubectl get pods -n "$NSP" --context "$CONTEXTO" -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c '^pagos-cruise-control.*|Running' || true)
if [ "$cc" -ge 1 ]; then r=0; else r=1; fi
verificar "Cruise Control desplegado y Running en pagos" "$r" "Habilita cruiseControl en el CR de pagos (guía 02)."

# 3. Historia de rebalanceo: add y remove en estado Ready (terminal exitoso).
add_st=$(kubectl get kafkarebalance agregar-broker-4 -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)
rem_st=$(kubectl get kafkarebalance vaciar-broker-4 -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.status.conditions[*].type}' 2>/dev/null || true)
if printf ' %s ' "$add_st" | grep -q ' Ready ' && printf ' %s ' "$rem_st" | grep -q ' Ready '; then r=0; else r=1; fi
verificar "Rebalanceos add y remove en estado terminal Ready (add=${add_st:-?}, remove=${rem_st:-?})" "$r" \
  "Ejecuta el ciclo add-brokers/remove-brokers con aprobación (guías 03-04)."

# 4. Pool de brokers en 3 réplicas (estado canónico restaurado).
nrep=$(kubectl get kafkanodepool brokers -n "$NSP" --context "$CONTEXTO" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
npods=$(kubectl get pods -n "$NSP" --context "$CONTEXTO" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c '^pagos-brokers-' || true)
if [ "$nrep" = "3" ] && [ "$npods" -eq 3 ]; then r=0; else r=1; fi
verificar "Pool de brokers en 3 réplicas (canónico) (replicas=${nrep:-?}, pods=${npods})" "$r" \
  "Escala el pool de brokers de vuelta a 3 (guía 04)."

# 5. DR en versión 4.2.0 (estado canónico tras el upgrade).
drver=$(kubectl get kafka dr -n "$NSD" --context "$CONTEXTO" -o jsonpath='{.spec.kafka.version}' 2>/dev/null || true)
if [ "$drver" = "4.2.0" ]; then r=0; else r=1; fi
verificar "DR en Kafka 4.2.0 (version=${drver:-?})" "$r" "Tras el upgrade, el DR queda en 4.2.0 (guía 06)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 07 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 07 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
