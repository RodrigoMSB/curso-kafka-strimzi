#!/usr/bin/env bash
# Test de estado del Lab 03 (estado final: tópicos gestionados, clúster
# endurecido, usuarios con ACLs y cuotas). Contrato del molde: todas las
# verificaciones, contadores dinámicos, pista por cada [ERROR], exit 0/1.
#
# Nota de diseño (desviación consciente): el test 90 del Lab 02 verificaba un
# round-trip por el listener PLANO (ANONYMOUS). Tras el endurecimiento de la
# parte 2, authorization deniega a ANONYMOUS, así que ese round-trip plano deja
# de funcionar A PROPÓSITO. Por eso aquí NO se hereda ese check: se verifican las
# invariantes de infraestructura del Lab 02 (clúster Ready, 1 controller + 3
# brokers) y el round-trip se hace AUTENTICADO (check 5).
#
# Las verificaciones 5 y 6 usan el pod 'cliente-kafka' (bin/01-preparar-cliente.sh).
set -uo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
TOPICO="pagos.meridiano.transacciones"

total=0; aprobadas=0
verificar() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas + 1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi
}
kexec() { kubectl exec cliente-kafka -n "$NS" --context "$CONTEXTO" -- "$@"; }

msg_info "Test del Lab 03 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

# 1. Invariantes de infraestructura del Lab 02 (sin round-trip plano).
ready=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
listado=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.status.phase}{"\n"}{end}' 2>/dev/null || true)
n_ctrl=$(printf '%s\n' "$listado" | grep -c '^pagos-controllers-.*|Running' || true)
n_brk=$(printf '%s\n' "$listado" | grep -c '^pagos-brokers-.*|Running' || true)
if [ "$ready" = "True" ] && [ "$n_ctrl" -eq 1 ] && [ "$n_brk" -eq 3 ]; then r=0; else r=1; fi
verificar "Clúster Kafka Ready con 1 controller + 3 brokers (infra Lab 02)" "$r" \
  "Recupera el estado base con bin/95-recuperar-lab.sh; revisa 'kubectl get kafka ${CLUSTER} -n ${NS}'."

# 2. Tópicos: transacciones y confirmaciones gestionados (Ready); tmp.pruebas.libre sin CR.
t_ready=$(kubectl get kafkatopic pagos.meridiano.transacciones -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
c_ready=$(kubectl get kafkatopic pagos.meridiano.confirmaciones -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if kubectl get kafkatopic tmp.pruebas.libre -n "$NS" --context "$CONTEXTO" >/dev/null 2>&1; then sin_cr=1; else sin_cr=0; fi
if [ "$t_ready" = "True" ] && [ "$c_ready" = "True" ] && [ "$sin_cr" -eq 0 ]; then r=0; else r=1; fi
verificar "KafkaTopics transacciones y confirmaciones Ready; tmp.pruebas.libre sin CR" "$r" \
  "Aplica soluciones/topics/ y revisa 'kubectl get kafkatopics -n ${NS}' (guía 01-02)."

# 3. CR endurecido: listeners 9093 tls + 9094 scram + authorization simple.
lst=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .spec.kafka.listeners[*]}{.port}:{.authentication.type}{"\n"}{end}' 2>/dev/null || true)
authz=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.spec.kafka.authorization.type}' 2>/dev/null || true)
if printf '%s\n' "$lst" | grep -q '^9093:tls$' \
   && printf '%s\n' "$lst" | grep -q '^9094:scram-sha-512$' \
   && [ "$authz" = "simple" ]; then r=0; else r=1; fi
verificar "Listeners 9093/tls y 9094/scram-sha-512 y authorization simple" "$r" \
  "Aplica soluciones/kafka/20-kafka-endurecido.yaml (guía 03)."

# 4. KafkaUsers Ready con sus Secrets.
u_ok=0
for u in app-pagos motor-fraude; do
  ur=$(kubectl get kafkauser "$u" -n "$NS" --context "$CONTEXTO" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  [ "$ur" = "True" ] || u_ok=1
  kubectl get secret "$u" -n "$NS" --context "$CONTEXTO" >/dev/null 2>&1 || u_ok=1
done
verificar "KafkaUsers app-pagos y motor-fraude Ready con sus Secrets" "$u_ok" \
  "Aplica soluciones/users/ y revisa 'kubectl get kafkausers -n ${NS}' (guía 04)."

# Guarda: el pod cliente debe existir para las verificaciones 5 y 6.
cliente_ok=0
kubectl get pod cliente-kafka -n "$NS" --context "$CONTEXTO" >/dev/null 2>&1 || cliente_ok=1

# 5. Round-trip AUTENTICADO: app-pagos produce (SCRAM), motor-fraude consume (mTLS).
if [ "$cliente_ok" -ne 0 ]; then
  r=1
else
  MARCA="humo-$(date +%s)-$$"
  kexec bash -c "echo '${MARCA}' | bin/kafka-console-producer.sh \
    --bootstrap-server pagos-kafka-bootstrap:9094 \
    --command-config /props/app-pagos.properties \
    --topic ${TOPICO}" >/dev/null 2>&1 || true
  consumido=$(kexec bash -c "bin/kafka-console-consumer.sh \
    --bootstrap-server pagos-kafka-bootstrap:9093 \
    --command-config /props/motor-fraude.properties \
    --topic ${TOPICO} --group fraude.deteccion \
    --from-beginning --timeout-ms 25000" 2>/dev/null || true)
  if printf '%s' "$consumido" | grep -q "$MARCA"; then r=0; else r=1; fi
fi
verificar "Round-trip autenticado (app-pagos produce SCRAM, motor-fraude consume mTLS)" "$r" \
  "Ejecuta bin/01-preparar-cliente.sh y revisa los Secrets/ACLs (guía 04)."

# 6. Prueba negativa: motor-fraude PRODUCIENDO debe ser RECHAZADO.
if [ "$cliente_ok" -ne 0 ]; then
  r=1; pista6="Ejecuta bin/01-preparar-cliente.sh."
else
  # Verdad de fondo: ¿el mensaje LLEGÓ al tópico? (el kafka-console-producer sale
  # con exit 0 aunque el broker rechace, así que el exit code no sirve). Se
  # combina con el patrón de autorización para distinguir un rechazo legítimo de
  # un fallo por otra causa (red, broker caído).
  MARCA_NEG="no-debe-pasar-$(date +%s)-$$"
  salida=$(kexec bash -c "echo '${MARCA_NEG}' | bin/kafka-console-producer.sh \
    --bootstrap-server pagos-kafka-bootstrap:9093 \
    --command-config /props/motor-fraude.properties \
    --topic ${TOPICO}" 2>&1 || true)
  llego=$(kexec bash -c "bin/kafka-console-consumer.sh \
    --bootstrap-server pagos-kafka-bootstrap:9093 \
    --command-config /props/motor-fraude.properties \
    --topic ${TOPICO} --group fraude.deteccion --timeout-ms 15000" 2>/dev/null \
    | grep -c "${MARCA_NEG}" || true)
  if [ "$llego" -gt 0 ]; then
    r=1; pista6="motor-fraude PRODUJO de verdad (su mensaje llegó al tópico): las ACLs no son de mínimo privilegio (guía 05)."
  elif printf '%s' "$salida" | grep -qiE "authoriz|not authorized"; then
    r=0; pista6=""
  else
    r=1; pista6="El mensaje no llegó pero tampoco hubo error de autorización (¿red, broker caído?). No es una prueba negativa válida; revisa la salida."
  fi
fi
verificar "Prueba negativa: motor-fraude NO puede producir (rechazo esperado)" "$r" "$pista6"

# 7. Cuota presente en el CR de app-pagos.
cuota=$(kubectl get kafkauser app-pagos -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.spec.quotas.producerByteRate}' 2>/dev/null || true)
if [ -n "$cuota" ]; then r=0; else r=1; fi
verificar "Cuota de producción presente en app-pagos (producerByteRate=${cuota:-ausente})" "$r" \
  "Añade spec.quotas.producerByteRate al KafkaUser app-pagos (guía 05)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 03 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 03 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
