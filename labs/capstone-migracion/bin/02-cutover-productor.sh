#!/usr/bin/env bash
# PLOMERÍA DEL NEGOCIO (provista): el CUTOVER. Detiene el productor del legado,
# registra el ÚLTIMO ID emitido, y arranca el productor "nuevo" escribiendo
# DIRECTO a la plataforma (pagos), con la identidad que se le pase.
#
# No decide la identidad por el alumno: el destino y las credenciales son
# parámetros. Los DEFAULTS apuntan a la solución de referencia (usuario
# 'transferencias', listener SCRAM interno de pagos). Las pistas orientan.
#
# El productor nuevo marca sus mensajes con "origen":"plataforma" y CONTINÚA la
# serie de IDs en último+1 — así el 90 verifica cero pérdida y cero duplicado en
# la frontera del cutover.
#
# Uso:
#   bin/02-cutover-productor.sh [--usuario U] [--secret S] [--bootstrap B] [--topico T]
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"

# Defaults = solución de referencia.
USUARIO="transferencias"
SECRET=""                         # por defecto = el nombre del usuario.
BOOTSTRAP="pagos-kafka-bootstrap:9094"
TOPICO="$LEGADO_TOPICO"

while [ $# -gt 0 ]; do
  case "$1" in
    --usuario)   USUARIO="$2"; shift 2 ;;
    --secret)    SECRET="$2"; shift 2 ;;
    --bootstrap) BOOTSTRAP="$2"; shift 2 ;;
    --topico)    TOPICO="$2"; shift 2 ;;
    *) msg_error "Parámetro desconocido: $1"; exit 2 ;;
  esac
done
[ -z "$SECRET" ] && SECRET="$USUARIO"

if ! legado_corriendo; then
  msg_error "El legado '${LEGADO_NOMBRE}' no está corriendo. ¿Ejecutaste 01-desplegar-legado.sh?"
  exit 1
fi

# 1. Detener el productor del legado (parada controlada por archivo).
msg_info "Cutover: deteniendo el productor del legado..."
docker exec "$LEGADO_NOMBRE" touch /tmp/legado-stop
sleep 3   # dejar que el loop termine su iteración en curso y persista el último ID.
ULTIMO=$(docker exec "$LEGADO_NOMBRE" cat /tmp/legado-ultimo-id 2>/dev/null || true)
if ! printf '%s' "$ULTIMO" | grep -q '^[0-9]\{1,\}$'; then
  msg_error "No pude leer el último ID del legado (/tmp/legado-ultimo-id='${ULTIMO}')."
  exit 1
fi
msg_ok "Productor del legado detenido. Último ID emitido por el legado: ${ULTIMO}."

# 2. Registrar la marca del cutover (la lee el 90 para verificar la frontera).
#    Merge-patch para NO borrar la 'semilla' que dejó el 01.
kubectl get configmap migracion-estado -n "$NSP" --context "$CONTEXTO" >/dev/null 2>&1 || \
  kubectl create configmap migracion-estado -n "$NSP" --context "$CONTEXTO" >/dev/null
kubectl patch configmap migracion-estado -n "$NSP" --context "$CONTEXTO" --type merge \
  -p "{\"data\":{\"ultimo-id-legado\":\"${ULTIMO}\",\"identidad-nueva\":\"${USUARIO}\"}}" >/dev/null
msg_ok "Marca de cutover registrada (ultimo-id-legado=${ULTIMO}, identidad=${USUARIO})."

INICIO=$((ULTIMO + 1))
IMG=$(imagen_kafka "$NSP" "$CONTEXTO")

# 3. Arrancar el productor NUEVO en la plataforma (Pod vivo; el negocio sigue).
#    La contraseña entra por secretKeyRef (no se interpola en el host). Las
#    variables de runtime del pod van escapadas (\$...) para expandirse DENTRO.
msg_info "Arrancando el productor nuevo en pagos como '${USUARIO}' (IDs desde ${INICIO})..."
kubectl delete pod productor-transferencias -n "$NSP" --context "$CONTEXTO" \
  --ignore-not-found --grace-period=1 >/dev/null 2>&1 || true
kubectl apply --context "$CONTEXTO" -f - <<POD
apiVersion: v1
kind: Pod
metadata:
  name: productor-transferencias
  namespace: ${NSP}
  labels:
    app: productor-transferencias
    rol: migracion
spec:
  restartPolicy: Never
  containers:
    - name: productor
      image: ${IMG}
      env:
        - name: USUARIO
          value: "${USUARIO}"
        - name: BOOTSTRAP
          value: "${BOOTSTRAP}"
        - name: TOPICO
          value: "${TOPICO}"
        - name: START
          value: "${INICIO}"
        - name: PASSWORD
          valueFrom:
            secretKeyRef:
              name: ${SECRET}
              key: password
      command: ["bash", "-c"]
      args:
        - |
          set -u
          printf 'security.protocol=SASL_PLAINTEXT\nsasl.mechanism=SCRAM-SHA-512\nsasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="%s" password="%s";\nenable.idempotence=false\nacks=all\n' "\$USUARIO" "\$PASSWORD" > /tmp/p.properties
          FIFO=/tmp/feed; rm -f "\$FIFO"; mkfifo "\$FIFO"
          /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "\$BOOTSTRAP" --producer.config /tmp/p.properties --topic "\$TOPICO" < "\$FIFO" &
          exec 3>"\$FIFO"
          n="\$START"
          while true; do
            printf '{"id":%d,"origen":"plataforma","tipo":"transferencia"}\n' "\$n" >&3
            n=\$((n + 1))
            sleep 1
          done
POD

msg_info "Esperando a que el productor nuevo esté Ready..."
kubectl wait --for=condition=Ready pod/productor-transferencias -n "$NSP" --context "$CONTEXTO" --timeout=120s
echo
msg_ok "CUTOVER EJECUTADO. Legado: hasta ID ${ULTIMO}. Plataforma: desde ID ${INICIO} (origen=plataforma)."
msg_info "El negocio ya escribe en la plataforma. Verifica paridad antes de decomisar el legado."
