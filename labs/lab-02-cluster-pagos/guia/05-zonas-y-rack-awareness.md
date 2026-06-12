# Guía 5 — Zonas y rack awareness

Tenemos tres brokers con datos a salvo en disco. Pero, ¿y si se cae una zona del
datacenter? Si las tres réplicas de una partición vivieran en la misma zona,
perderla las perdería todas. Rack awareness reparte las réplicas entre zonas.

## 1. Simula tres zonas etiquetando los workers

En el laboratorio no hay zonas reales, pero podemos simularlas: Kubernetes usa
la etiqueta estándar `topology.kubernetes.io/zone` para indicar en qué zona está
cada nodo. Etiquetamos los tres workers con `zona-a`, `zona-b` y `zona-c`:

```bash
bash bin/01-etiquetar-zonas.sh
```

Verifica:

```bash
kubectl get nodes -L topology.kubernetes.io/zone
```

```text
Salida esperada (puede variar levemente)
NAME                      STATUS   ROLES           ...   ZONE
meridiano-control-plane   Ready    control-plane   ...
meridiano-worker          Ready    <none>          ...   zona-a
meridiano-worker2         Ready    <none>          ...   zona-b
meridiano-worker3         Ready    <none>          ...   zona-c
```

## 2. Habilita rack awareness en el clúster

Ahora le decimos a Kafka que use esa etiqueta como "rack". En tu copia del
`Kafka`, completa el bloque `rack` (TODO D de la plantilla):

**ANTES** (comentado en la plantilla):

```yaml
  kafka:
    version: 4.2.0
    metadataVersion: 4.2-IV1
    # rack:
    #   topologyKey: # TODO
```

**DESPUÉS**:

```yaml
  kafka:
    version: 4.2.0
    metadataVersion: 4.2-IV1
    rack:
      topologyKey: topology.kubernetes.io/zone
```

Aplícalo:

```bash
kubectl apply -n meridiano-pagos -f mi-kafka.yaml
```

El operador hará un **rolling update**: reinicia los brokers de a uno, sin
cortar el servicio, para inyectarles su zona. Obsérvalo:

```bash
kubectl get pods -n meridiano-pagos -w
```

Espera a que termine (todos `Running` de nuevo) y a que el clúster vuelva a Ready:

```bash
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=300s
```

Con `rack` habilitado, cada broker conoce su zona y Kafka coloca las réplicas de
cada partición en zonas distintas.

## 3. Verifica la distribución entre zonas

Mira de nuevo el reparto del tópico:

```bash
kubectl run cli-describe --rm -i --restart=Never \
  -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-topics.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --describe --topic pagos.meridiano.transacciones
```

Cada partición lista sus tres réplicas en los tres brokers (`Replicas: 1,2,3`).
Como cada broker vive en una zona distinta, las tres réplicas de cada partición
caen en tres zonas distintas: perder una zona deja siempre dos réplicas vivas.

> Con exactamente 3 brokers en 3 zonas, "una réplica por broker" ya es "una
> réplica por zona". El valor de rack awareness se nota cuando hay más brokers
> que zonas: ahí evita que dos réplicas de la misma partición caigan juntas.

## Verificación final del lab

```bash
bash bin/90-test-lab.sh
```

Debe terminar con todas las verificaciones en verde: clúster Ready, 1 controller
+ 3 brokers, PVCs Bound, zonas etiquetadas, rack habilitado, tópico con RF=3 y un
round-trip de humo correcto.

## Desafío extra (post-sesión): tumbar una zona

Ya tienes todo para el desafío: cordona el worker de una zona, borra el broker
que vive ahí y comprueba que producir y consumir **siguen funcionando** con dos
réplicas en sincronía (`min.insync.replicas=2`). La resolución paso a paso está
en `soluciones/desafio-zona.md`.

## Cierre

El operador recibió su primer encargo y lo cumplió: un clúster de pagos con tres
brokers, datos persistentes y réplicas repartidas en tres zonas. Meridiano ya
tiene plataforma. En el Lab 03 dejamos de crear tópicos a mano y empezamos a
gestionarlos como código.
