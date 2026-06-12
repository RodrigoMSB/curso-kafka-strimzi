# Desafío extra (parte 1) — MM2 descubre un tópico nuevo

> Objetivo: comprobar que MM2 replica automáticamente un tópico nuevo que calce
> con el patrón, sin tocar el CR de MM2.

## 1. Crea un tópico nuevo en `pagos`

Como `connect-cdc` no, usa el Topic Operator (declarativo) o créalo con un
KafkaTopic que calce con `pagos.meridiano.*`:

```bash
cat <<'EOF' | kubectl apply -n meridiano-pagos -f -
apiVersion: kafka.strimzi.io/v1
kind: KafkaTopic
metadata:
  name: pagos.meridiano.alertas
  labels:
    strimzi.io/cluster: pagos
spec:
  partitions: 3
  replicas: 3
  config:
    min.insync.replicas: "2"
EOF
```

## 2. Produce un mensaje en el tópico nuevo

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'echo "alerta-1" | bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --producer.config /props/app-pagos.properties \
   --topic pagos.meridiano.alertas'
```

> Si `app-pagos` no tiene Write sobre el tópico nuevo (sus ACLs eran solo para
> transacciones), produce con un usuario que sí pueda, o amplía sus ACLs. La idea
> del desafío es la REPLICACIÓN automática, no el productor.

## 3. Verifica que MM2 lo replicó solo

MM2 refresca su lista de tópicos cada `refresh.topics.interval.seconds` (30s en
este lab). Tras ese intervalo, el tópico aparece en el DR:

```bash
kubectl run dr-ls --rm -i --restart=Never -n meridiano-dr \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-topics.sh --bootstrap-server dr-kafka-bootstrap.meridiano-dr.svc:9092 --list | grep alertas
```

`pagos.meridiano.alertas` aparece en el DR sin que tocaras el CR de MM2: el
patrón `pagos.meridiano.*` ya lo incluía, y el refresco automático lo descubrió.
Así, cuando el negocio crea tópicos nuevos, el DR los cubre sin intervención.
