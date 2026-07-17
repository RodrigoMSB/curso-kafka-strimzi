#!/usr/bin/env bash
# Test de estado del Lab 04 (estado final: dos listeners externos, puerta plana
# cerrada). Contrato del molde. Las verificaciones 4 y 5 usan kcat DESDE EL HOST.
set -uo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"
CLUSTER="pagos"
TOPICO="pagos.meridiano.transacciones"
DIR_CRED="$DIR_SCRIPT/../credenciales"
LAB03_90="$DIR_SCRIPT/../../lab-03-topicos-identidad/bin/90-test-lab.sh"

total=0; aprobadas=0
verificar() {
  total=$((total + 1))
  if [ "$2" -eq 0 ]; then aprobadas=$((aprobadas + 1)); msg_ok "$1"; else msg_error "$1 -> $3"; fi
}

kcat_scram() { kcat -b 127.0.0.1:32000 -X security.protocol=SASL_SSL \
  -X sasl.mechanisms=SCRAM-SHA-512 -X sasl.username=app-pagos \
  -X sasl.password="$(cat "$DIR_CRED/app-pagos.password" 2>/dev/null)" \
  -X ssl.ca.location="$DIR_CRED/ca.crt" "$@"; }
kcat_mtls() { kcat -b 127.0.0.1:32004 -X security.protocol=SSL \
  -X ssl.ca.location="$DIR_CRED/ca.crt" \
  -X ssl.certificate.location="$DIR_CRED/motor-fraude.crt" \
  -X ssl.key.location="$DIR_CRED/motor-fraude.key" "$@"; }

msg_info "Test del Lab 04 (clúster objetivo: ${NOMBRE_CLUSTER})"
echo

# Refresca credenciales locales (idempotente).
bash "$DIR_SCRIPT/01-extraer-credenciales.sh" >/dev/null 2>&1 || true

# 1. Estado del Lab 03 (round-trip autenticado interno, usuarios, etc.).
if [ -f "$LAB03_90" ] && bash "$LAB03_90" >/tmp/lab04-lab03-90.out 2>&1; then r=0; else r=1; fi
verificar "Estado del Lab 03 intacto (su test 90 en verde)" "$r" \
  "Recupera con bin/95-recuperar-lab.sh; detalle en /tmp/lab04-lab03-90.out"

# 2. Listeners externos en el CR (extscram + extmtls) con TLS, y status publicado.
lst=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .spec.kafka.listeners[*]}{.name}:{.type}:{.tls}{"\n"}{end}' 2>/dev/null || true)
nlisten_status=$(kubectl get kafka "$CLUSTER" -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.listeners[*].name}' 2>/dev/null || true)
if printf '%s\n' "$lst" | grep -q '^extscram:nodeport:true$' \
   && printf '%s\n' "$lst" | grep -q '^extmtls:nodeport:true$' \
   && printf '%s' "$nlisten_status" | grep -q 'extscram'; then r=0; else r=1; fi
verificar "Listeners externos extscram y extmtls (nodeport+TLS) con direcciones publicadas" "$r" \
  "Aplica soluciones/parte-1-con-plano/ (guía 02) y luego parte-2-sin-plano/ (guía 05)."

# 3. Listener plano 9092 AUSENTE del CR (la puerta vieja no existe).
if printf '%s\n' "$lst" | grep -qi 'plain'; then r=1; else r=0; fi
verificar "Listener plano 9092 ausente del CR (puerta vieja cerrada)" "$r" \
  "Elimina el listener plano del CR (guía 05)."

# kcat presente para 4 y 5.
kcat_ok=0; verificar_comando kcat || kcat_ok=1

# 4. Round-trip EXTERNO: app-pagos produce por SCRAM, motor-fraude consume por mTLS.
if [ "$kcat_ok" -ne 0 ]; then r=1
else
  MARCA="ext-$(date +%s)-$$"
  printf '%s\n' "$MARCA" | kcat_scram -t "$TOPICO" -P >/dev/null 2>&1 || true
  consumido=$(kcat_mtls -t "$TOPICO" -C -e -o beginning -q 2>/dev/null || true)
  if printf '%s' "$consumido" | grep -q "$MARCA"; then r=0; else r=1; fi
fi
verificar "Round-trip externo con kcat (SCRAM produce + mTLS consume)" "$r" \
  "Instala kcat y revisa los listeners/credenciales (guías 03-04)."

# 5. mTLS externo: motor-fraude obtiene metadata por el listener mTLS.
if [ "$kcat_ok" -ne 0 ]; then r=1
else
  meta=$(kcat_mtls -L 2>/dev/null || true)
  if printf '%s' "$meta" | grep -q "$TOPICO"; then r=0; else r=1; fi
fi
verificar "Conexión mTLS externa (motor-fraude) lista metadata del tópico" "$r" \
  "Revisa el certificado de cliente y el listener extmtls (guía 04)."

# 6. Conexión interna al puerto plano 9092 -> falla por CONEXIÓN (puerta inexistente).
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"
salida9092=$(kubectl run "cli-9092-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image="$IMG" --command -- bin/kafka-broker-api-versions.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 2>&1 || true)
# Falla por CONEXIÓN (no hay listener) y NO por autorización: esa es la moraleja.
if printf '%s' "$salida9092" | grep -qiE "Request METADATA failed|Connection refused|could not be established|disconnect|Connection to node|Failed to" \
   && ! printf '%s' "$salida9092" | grep -qi "Authorization"; then r=0; else r=1; fi
verificar "El puerto plano 9092 rechaza la conexión (no es un fallo de autorización)" "$r" \
  "Si responde o falla por autorización, el listener plano sigue presente: elimínalo del CR (guía 05)."

# 7. Kafka Bridge (la puerta HTTP, guía 06) en estado Ready.
br_ready=$(kubectl get kafkabridge puente-http -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [ "$br_ready" = "True" ]; then r=0; else r=1; fi
verificar "Kafka Bridge 'puente-http' en estado Ready" "$r" \
  "Aplica tu mi-bridge.yaml o soluciones/30-bridge.yaml (guía 06)."

# 8. Round-trip del puente: producir por HTTP (curl al bridge) y consumirlo por
#    Kafka en la partición:offset exacta que devuelve el bridge (robusto frente al
#    backlog del tópico). Prueba el TRADUCTOR, no que el pod esté vivo.
BRMARCA="bridge-90-$(date +%s)-$$"
resp=$(kubectl run "cli-brhttp-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
  --image=curlimages/curl:latest --command -- \
  curl -s -X POST http://puente-http-bridge-service:8080/topics/pagos.meridiano.http \
  -H 'Content-Type: application/vnd.kafka.json.v2+json' \
  -d "{\"records\":[{\"value\":{\"marca\":\"${BRMARCA}\"}}]}" 2>/dev/null || true)
brpart=$(printf '%s' "$resp" | grep -oE '"partition":[0-9]+' | grep -oE '[0-9]+' | head -1)
broff=$(printf '%s' "$resp" | grep -oE '"offset":[0-9]+' | grep -oE '[0-9]+' | head -1)
brpw=$(kubectl get secret bridge-http -n "$NS" --context "$CONTEXTO" -o jsonpath='{.data.password}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)
brmsg=""
if [ -n "$brpart" ] && [ -n "$broff" ] && [ -n "$brpw" ]; then
  brmsg=$(kubectl run "cli-brk-$$" --rm -i --restart=Never -n "$NS" --context "$CONTEXTO" \
    --image="$IMG" --command -- bash -c "
      printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"bridge-http\" password=\"${brpw}\";\n' > /tmp/c.properties
      bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9094 --consumer.config /tmp/c.properties \
        --topic pagos.meridiano.http --partition ${brpart} --offset ${broff} --max-messages 1 --timeout-ms 20000" 2>/dev/null || true)
fi
if printf '%s' "$brmsg" | grep -q "$BRMARCA"; then r=0; else r=1; fi
verificar "Round-trip del puente: producido por HTTP y consumido por Kafka" "$r" \
  "Revisa el Bridge Ready, las ACLs de bridge-http y el tópico pagos.meridiano.http (guía 06)."

echo
if [ "$aprobadas" -eq "$total" ]; then
  msg_ok "${aprobadas}/${total} verificaciones correctas"
  msg_ok "Lab 04 completado correctamente"
  exit 0
else
  msg_error "${aprobadas}/${total} verificaciones correctas"
  msg_error "Lab 04 incompleto: revisa los [ERROR] de arriba"
  exit 1
fi
