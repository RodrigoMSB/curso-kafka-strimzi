# Guía 2 — Reconciliación, drift y convivencia

Con los tópicos declarados, el operador los **reconcilia**: mantiene Kafka
alineado con lo que dice el `KafkaTopic`. Veámoslo en acción.

## 1. Reconciliación: cambiar la retención por YAML

Edita tu `mi-transacciones.yaml` y añade una retención de 7 días:

**ANTES**:

```yaml
spec:
  partitions: 3
  replicas: 3
  config:
    min.insync.replicas: "2"
```

**DESPUÉS**:

```yaml
spec:
  partitions: 3
  replicas: 3
  config:
    min.insync.replicas: "2"
    retention.ms: "604800000"
```

Aplica y verifica que el clúster lo refleja, leyendo la config real del tópico
desde un pod cliente:

```bash
kubectl apply -n meridiano-pagos -f mi-transacciones.yaml

kubectl run cli-config --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-configs.sh --bootstrap-server pagos-kafka-bootstrap:9092 \
  --describe --entity-type topics --entity-name pagos.meridiano.transacciones
```

Entre la salida verás `retention.ms=604800000`. Lo que declaraste, el operador
lo hizo realidad.

## 2. El drift y su reversión (la demo estrella)

Ahora hagamos trampa: cambiemos la retención **por CLI**, saltándonos el
`KafkaTopic`, como haría alguien "arreglando algo rápido" en producción.

```bash
kubectl run cli-drift --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-configs.sh --bootstrap-server pagos-kafka-bootstrap:9092 \
  --alter --entity-type topics --entity-name pagos.meridiano.transacciones \
  --add-config retention.ms=3600000
```

Acabas de crear **drift**: la realidad (1 hora) ya no coincide con lo declarado
(7 días). El Topic Operator unidireccional reconcilia periódicamente y, en su
siguiente pasada, **revierte** el cambio: vuelve a poner `retention.ms=604800000`.

Espera la reconciliación y vuelve a describir el tópico:

```bash
# vuelve a ejecutar el kafka-configs.sh --describe de arriba cada cierto tiempo
```

Tras unos segundos —la reconciliación periódica del Topic Operator; en este lab
se observó en torno a **~50 segundos**— `retention.ms` vuelve a su valor declarado:

```text
Salida esperada (puede variar levemente)
  retention.ms=604800000 sensitive=false ...
```

El operador **revirtió** el cambio: tu drift no sobrevivió. (Si la doc o tu
entorno muestran un intervalo distinto, espera a la siguiente reconciliación
antes de dar por hecho que no se revierte: es el "reloj del drift".)

La lección: en una plataforma gestionada por código, los cambios a mano no
sobreviven. La fuente de verdad es el repositorio, no la terminal. Esto es lo
que hace fiable a GitOps.

## 3. Convivencia con lo no gestionado

¿El operador toca **todos** los tópicos? No. Solo los que tienen `KafkaTopic`.
Creemos uno libre, sin CR, y comprobémoslo:

```bash
kubectl run cli-libre --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-topics.sh --bootstrap-server pagos-kafka-bootstrap:9092 \
  --create --topic tmp.pruebas.libre --partitions 1 --replication-factor 3
```

`tmp.pruebas.libre` existe en Kafka pero **no** tiene `KafkaTopic`:

```bash
kubectl get kafkatopics -n meridiano-pagos
```

No aparece en la lista de CRs. El operador no lo gestiona ni lo toca. La regla de
Meridiano: **los tópicos de negocio se declaran; los efímeros de prueba quedan
libres.**

## Cierre de la parte 1

```bash
kubectl get kafkatopics -n meridiano-pagos
```

Esa lista es tu **inventario vivo** de tópicos de negocio: con dueño, con
historia y bajo control. En el capstone, este inventario se gestiona con GitOps
(un repositorio que el clúster sigue automáticamente).
