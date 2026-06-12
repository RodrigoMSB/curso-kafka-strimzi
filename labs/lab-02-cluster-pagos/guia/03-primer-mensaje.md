# Guía 3 — El primer mensaje del banco

El clúster está vivo. Hora de mandar el primer mensaje de pagos de Meridiano.

## El tópico, creado "a la antigua"

Vamos a crear el tópico `pagos.meridiano.transacciones` con la herramienta
clásica de Kafka, `kafka-topics.sh`, ejecutada desde un **pod cliente efímero**
dentro del clúster. No instalamos nada en tu máquina: levantamos un pod con la
imagen de Kafka de Strimzi, corremos el comando y el pod se borra solo (`--rm`).

```bash
kubectl run cli-topico --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-topics.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --create --topic pagos.meridiano.transacciones \
  --partitions 3 --replication-factor 3 \
  --config min.insync.replicas=2
```

Tres decisiones en ese comando:

- **`--partitions 3`** — tres particiones para repartir la carga.
- **`--replication-factor 3`** — cada partición se copia en los tres brokers.
- **`--config min.insync.replicas=2`** — una escritura se confirma cuando al
  menos 2 de las 3 réplicas la tienen. Es el seguro de durabilidad de un pago.

`pagos-kafka-bootstrap:9092` es el servicio interno del listener `plain` que
declaramos en el `Kafka`. Es la puerta por la que entran los clientes de dentro
del clúster.

> **Esto que hicimos a mano hoy, en el próximo capítulo se convierte en código.**
> En el Lab 03 declararás el tópico con un `KafkaTopic` y el Topic Operator lo
> creará y vigilará por ti — y verás por qué la gestión declarativa le gana a
> `kafka-topics.sh` en un banco. Por hoy, lo creamos a la antigua a propósito.

Confirma que existe y cómo quedó repartido:

```bash
kubectl run cli-describe --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-topics.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --describe --topic pagos.meridiano.transacciones
```

```text
Salida esperada (puede variar levemente)
Topic: pagos.meridiano.transacciones  PartitionCount: 3  ReplicationFactor: 3  Configs: min.insync.replicas=2
  Partition: 0  Leader: 2  Replicas: 2,0,1  Isr: 2,0,1
  Partition: 1  Leader: 0  Replicas: 0,1,2  Isr: 0,1,2
  Partition: 2  Leader: 1  Replicas: 1,2,0  Isr: 1,2,0
```

Cada partición tiene sus 3 réplicas en los 3 brokers. Guarda esta foto: en la
guía 05 volveremos a ella para ver las zonas.

## Producir: el primer pago

Levanta un productor y escribe un mensaje. Cada línea que tecleas es un mensaje;
cierra con `Ctrl-D`.

```bash
kubectl run cli-productor --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones
```

Escribe, por ejemplo:

```text
{"id":"TX-0001","origen":"meridiano","monto":15000}
```

## Consumir: leerlo de vuelta

Ahora léelo desde el principio del tópico:

```bash
kubectl run cli-consumidor --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones \
  --from-beginning --timeout-ms 15000
```

```text
Salida esperada (puede variar levemente)
{"id":"TX-0001","origen":"meridiano","monto":15000}
```

Ese es el primer pago de Banco Meridiano viajando por su nueva plataforma. El
clúster funciona de punta a punta.

Disfruta el momento… y guárdalo en la memoria, porque en la siguiente guía vamos
a romperlo a propósito.
