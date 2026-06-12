#!/usr/bin/env bash
# Plomería NO pedagógica: extrae las credenciales de los Secrets de los usuarios
# y arma los archivos de propiedades de cliente (SCRAM y mTLS) en un ConfigMap,
# y deja un pod 'cliente-kafka' vivo con todo montado para producir/consumir.
#
# Decodifica base64 con openssl (portable en macOS y WSL2; sin GNU-ismos).
# LAB01_CLUSTER permite apuntar a otro clúster.
set -euo pipefail

DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NS="meridiano-pagos"

# Decodifica un valor base64 de una sola línea de forma portable.
b64d() { openssl base64 -d -A; }

# 1. Los Secrets deben existir (los crean los KafkaUser y el clúster).
for s in app-pagos motor-fraude pagos-cluster-ca-cert; do
  if ! kubectl get secret "$s" -n "$NS" --context "$CONTEXTO" >/dev/null 2>&1; then
    msg_error "No existe el Secret '$s'. ¿Están los KafkaUser y el clúster Ready?"
    exit 1
  fi
done

# 2. Lee las contraseñas de los Secrets.
PWD_SCRAM=$(kubectl get secret app-pagos -n "$NS" --context "$CONTEXTO" -o jsonpath='{.data.password}' | b64d)
PWD_USER_P12=$(kubectl get secret motor-fraude -n "$NS" --context "$CONTEXTO" -o jsonpath='{.data.user\.password}' | b64d)
PWD_CA_P12=$(kubectl get secret pagos-cluster-ca-cert -n "$NS" --context "$CONTEXTO" -o jsonpath='{.data.ca\.password}' | b64d)

# 3. Arma los properties en un directorio temporal.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cliente-pagos.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/app-pagos.properties" <<PROP
bootstrap.servers=pagos-kafka-bootstrap:9094
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="app-pagos" password="${PWD_SCRAM}";
enable.idempotence=false
acks=all
PROP

cat > "$TMP/motor-fraude.properties" <<PROP
bootstrap.servers=pagos-kafka-bootstrap:9093
security.protocol=SSL
ssl.keystore.type=PKCS12
ssl.keystore.location=/secrets/motor-fraude/user.p12
ssl.keystore.password=${PWD_USER_P12}
ssl.truststore.type=PKCS12
ssl.truststore.location=/secrets/ca/ca.p12
ssl.truststore.password=${PWD_CA_P12}
# Idempotencia desactivada: así una escritura no autorizada falla a nivel de
# TÓPICO (Write denegado) y no a nivel de CLUSTER (IdempotentWrite). Lección más
# clara en la prueba negativa. Para el consumidor, estas dos líneas se ignoran.
enable.idempotence=false
acks=all
PROP

# 4. ConfigMap con los properties (idempotente).
kubectl create configmap cliente-props -n "$NS" --context "$CONTEXTO" \
  --from-file="$TMP/app-pagos.properties" \
  --from-file="$TMP/motor-fraude.properties" \
  --dry-run=client -o yaml | kubectl apply --context "$CONTEXTO" -f -

# 5. Imagen de Kafka tomada de un broker real.
IMG=$(kubectl get pods -n "$NS" --context "$CONTEXTO" \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null \
  | grep '^pagos-brokers-' | head -1 | cut -d' ' -f2)
[ -z "$IMG" ] && IMG="quay.io/strimzi/kafka:0.51.0-kafka-4.2.0"

# 6. Pod cliente con props y secretos montados, vivo para producir/consumir.
# Se recrea siempre para que tome los properties actuales del ConfigMap (un pod
# existente no recargaría el ConfigMap montado de inmediato).
kubectl delete pod cliente-kafka -n "$NS" --context "$CONTEXTO" --ignore-not-found --grace-period=1 >/dev/null 2>&1 || true
cat <<POD | kubectl apply --context "$CONTEXTO" -f -
apiVersion: v1
kind: Pod
metadata:
  name: cliente-kafka
  namespace: ${NS}
  labels:
    app: cliente-kafka
spec:
  restartPolicy: Never
  containers:
    - name: cliente
      image: ${IMG}
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: props
          mountPath: /props
        - name: motor-fraude
          mountPath: /secrets/motor-fraude
        - name: ca
          mountPath: /secrets/ca
  volumes:
    - name: props
      configMap:
        name: cliente-props
    - name: motor-fraude
      secret:
        secretName: motor-fraude
    - name: ca
      secret:
        secretName: pagos-cluster-ca-cert
POD

msg_info "Esperando a que el pod cliente-kafka esté listo..."
kubectl wait --for=condition=Ready pod/cliente-kafka -n "$NS" --context "$CONTEXTO" --timeout=120s
msg_ok "Pod 'cliente-kafka' listo. Properties en /props; secretos en /secrets."
