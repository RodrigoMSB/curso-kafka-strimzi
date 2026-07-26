#!/usr/bin/env bash
# PLOMERÍA (provista, no diseñada por el alumno): levanta el "Kafka legado" de
# Banco Meridiano. Un contenedor Docker FUERA del clúster kind pero EN su red
# (mismo patrón que el registry del Lab 05), single-node KRaft, listener
# PLAINTEXT sin TLS ni auth — es legado, "así vivíamos".
#
# Hace tres cosas:
#   1. Arranca el contenedor 'kafka-legado' en la red 'kind' (alcanzable desde
#      los pods por su nombre: kafka-legado:9092).
#   2. Crea 'legado.transferencias' (3 particiones, RF=1) y SIEMBRA N mensajes de
#      historia con IDs secuenciales 1..N (N conocido = paridad verificable).
#   3. Deja un PRODUCTOR CONTINUO vivo dentro del contenedor (1 msg/s, IDs
#      continuando la serie desde N+1), con parada controlada para el cutover.
#
# De-risk (reportado): la imagen del curso falla al iniciar si LOG_DIR no es
# escribible (intenta el gc.log en /opt/kafka/logs); por eso LOG_DIR=/tmp/logs.
# Y advertised.listeners DEBE ser el nombre del contenedor (no localhost) para
# que el cliente, tras el bootstrap, conecte a una dirección que el pod resuelve.
#
# Idempotente: si el contenedor ya corre, no hace nada.
set -euo pipefail
DIR_SCRIPT="$(cd "$(dirname "$0")" && pwd)"
. "$DIR_SCRIPT/lib-comunes.sh"

NOMBRE_CLUSTER="${LAB01_CLUSTER:-meridiano}"
CONTEXTO="kind-${NOMBRE_CLUSTER}"
NSP="meridiano-pagos"
RED_KIND="kind"
SEMILLA="${LEGADO_SEMILLA:-5000}"   # N mensajes de historia (IDs 1..N).

if legado_corriendo; then
  msg_info "El legado '${LEGADO_NOMBRE}' ya está corriendo. Nada que hacer (idempotente)."
  exit 0
fi

# 1. Arrancar el contenedor del Kafka legado en la red de kind.
msg_info "Arrancando el Kafka legado '${LEGADO_NOMBRE}' en la red '${RED_KIND}'..."
docker rm -f "$LEGADO_NOMBRE" >/dev/null 2>&1 || true
# MSYS_NO_PATHCONV en línea: las rutas son del contenedor, no del host (Git Bash).
MSYS_NO_PATHCONV=1 docker run -d --name "$LEGADO_NOMBRE" --network "$RED_KIND" \
  -p "127.0.0.1:19092:9092" \
  -e LOG_DIR=/tmp/logs \
  -e KAFKA_HEAP_OPTS="-Xms256m -Xmx256m" \
  --entrypoint /bin/bash "$LEGADO_IMG" -c '
set -e
mkdir -p /tmp/logs /tmp/kraft-logs
CFG=/tmp/server.properties
{
  echo "process.roles=broker,controller"
  echo "node.id=1"
  echo "controller.quorum.voters=1@127.0.0.1:9093"
  echo "listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
  echo "advertised.listeners=PLAINTEXT://kafka-legado:9092"
  echo "listener.security.protocol.map=PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT"
  echo "controller.listener.names=CONTROLLER"
  echo "inter.broker.listener.name=PLAINTEXT"
  echo "log.dirs=/tmp/kraft-logs"
  echo "num.partitions=3"
  echo "offsets.topic.replication.factor=1"
  echo "transaction.state.log.replication.factor=1"
  echo "transaction.state.log.min.isr=1"
  echo "default.replication.factor=1"
} > "$CFG"
CID=$(/opt/kafka/bin/kafka-storage.sh random-uuid)
/opt/kafka/bin/kafka-storage.sh format -t "$CID" -c "$CFG" --ignore-formatted
exec /opt/kafka/bin/kafka-server-start.sh "$CFG"
' >/dev/null
msg_ok "Contenedor '${LEGADO_NOMBRE}' creado (host 127.0.0.1:19092; pods: ${LEGADO_NOMBRE}:9092)."

# 2. Esperar a que el broker legado responda.
msg_info "Esperando a que el broker legado responda..."
arriba=0
for i in $(seq 1 30); do
  # MSYS_NO_PATHCONV en línea: las rutas son del contenedor, no del host (Git Bash).
  if MSYS_NO_PATHCONV=1 docker exec "$LEGADO_NOMBRE" /opt/kafka/bin/kafka-broker-api-versions.sh \
      --bootstrap-server localhost:9092 >/dev/null 2>&1; then
    arriba=1; break
  fi
  sleep 5
done
if [ "$arriba" -ne 1 ]; then
  msg_error "El broker legado no arrancó a tiempo. Logs:"; docker logs "$LEGADO_NOMBRE" 2>&1 | tail -15
  exit 1
fi
msg_ok "Broker legado operativo."

# 3. Tópico de historia + siembra de N mensajes (IDs 1..N).
msg_info "Creando '${LEGADO_TOPICO}' (3 particiones, RF=1) y sembrando ${SEMILLA} mensajes..."
# MSYS_NO_PATHCONV en línea: las rutas son del contenedor, no del host (Git Bash).
MSYS_NO_PATHCONV=1 docker exec "$LEGADO_NOMBRE" /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --if-not-exists --topic "$LEGADO_TOPICO" --partitions 3 --replication-factor 1 >/dev/null 2>&1
docker exec "$LEGADO_NOMBRE" bash -c '
  N='"$SEMILLA"'; i=1
  while [ "$i" -le "$N" ]; do
    printf "{\"id\":%d,\"origen\":\"legado\",\"tipo\":\"transferencia\"}\n" "$i"
    i=$((i+1))
  done | /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic '"$LEGADO_TOPICO"'
'
msg_ok "Sembrados ${SEMILLA} mensajes de historia (IDs 1..${SEMILLA})."

# 4. Productor continuo: un solo JVM alimentado por un FIFO; el feeder escribe
#    1 msg/s con IDs desde N+1. Parada controlada por archivo (captura el último
#    ID de forma fiable para el cutover). PID del feeder en /tmp/legado-feeder.pid.
msg_info "Instalando y arrancando el productor continuo del legado (1 msg/s desde ID $((SEMILLA+1)))..."
docker exec -i "$LEGADO_NOMBRE" bash -c 'cat > /tmp/productor-legado.sh' <<'PROD'
#!/usr/bin/env bash
set -u
START="${1:-5001}"
TOPICO="legado.transferencias"
FIFO=/tmp/feed-legado
rm -f "$FIFO" /tmp/legado-stop; mkfifo "$FIFO"
/opt/kafka/bin/kafka-console-producer.sh --bootstrap-server localhost:9092 --topic "$TOPICO" < "$FIFO" &
echo $! > /tmp/legado-jvm.pid
exec 3>"$FIFO"
n="$START"
while [ ! -f /tmp/legado-stop ]; do
  printf '{"id":%d,"origen":"legado","tipo":"transferencia"}\n' "$n" >&3
  echo "$n" > /tmp/legado-ultimo-id
  n=$((n+1))
  sleep 1
done
exec 3>&-
kill "$(cat /tmp/legado-jvm.pid 2>/dev/null)" 2>/dev/null || true
PROD
docker exec -d "$LEGADO_NOMBRE" bash -c 'bash /tmp/productor-legado.sh '"$((SEMILLA+1))"' & echo $! > /tmp/legado-feeder.pid'
msg_ok "Productor continuo en marcha (negocio vivo escribiendo al legado)."

# 5. Registrar la línea base de la migración en un ConfigMap (sobrevive al
#    decomiso del contenedor; lo lee el 90 para la verificación de paridad).
if kubectl get ns "$NSP" --context "$CONTEXTO" >/dev/null 2>&1; then
  kubectl create configmap migracion-estado -n "$NSP" --context "$CONTEXTO" \
    --from-literal=semilla="$SEMILLA" \
    --dry-run=client -o yaml | kubectl apply --context "$CONTEXTO" -f - >/dev/null
  msg_ok "Línea base registrada en ConfigMap 'migracion-estado' (semilla=${SEMILLA})."
else
  msg_info "Namespace ${NSP} ausente; omito el ConfigMap de línea base (¿plataforma sin desplegar?)."
fi

echo
msg_ok "Legado desplegado: historia (${SEMILLA}) + tráfico vivo. Listo para migrar."
