# Desafío extra — "tumbar una zona"

> Objetivo: comprobar que el clúster de pagos sobrevive a la caída completa de
> una zona. Con replication factor 3 y `min.insync.replicas=2`, perder una de
> tres zonas deja dos réplicas en sincronía: el tópico sigue aceptando
> escrituras y lecturas.

Todos los comandos asumen el contexto `kind-meridiano` y el namespace
`meridiano-pagos`. Ajusta el nombre de la zona a una de las etiquetadas
(`zona-a`, `zona-b`, `zona-c`).

## 1. Identifica el worker de una zona y su broker

```bash
# Worker de la zona-c
kubectl get nodes -l topology.kubernetes.io/zone=zona-c

# Pods de broker y en qué nodo corre cada uno
kubectl get pods -n meridiano-pagos -o wide | grep pagos-brokers
```

## 2. "Tumba" la zona: cordona el nodo y borra el broker que vive ahí

Cordonar evita que el pod se reprograme en ese mismo nodo mientras dure el
ejercicio (simula que la zona no está disponible):

```bash
kubectl cordon <worker-de-zona-c>
kubectl delete pod <pod-broker-en-zona-c> -n meridiano-pagos
```

El pod quedará en estado `Pending` (no hay otro nodo en su zona y el nodo está
cordonado). El clúster ahora opera con 2 de 3 brokers.

## 3. Verifica que producir y consumir sigue funcionando

```bash
# Producir
echo "pago-durante-caida-de-zona" | kubectl run cli-prod --rm -i --restart=Never \
  -n meridiano-pagos --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 -- \
  bin/kafka-console-producer.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones

# Consumir
kubectl run cli-cons --rm -i --restart=Never \
  -n meridiano-pagos --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones \
  --from-beginning --timeout-ms 15000
```

Debe aparecer `pago-durante-caida-de-zona` entre los mensajes: con 2 réplicas en
sincronía (`min.insync.replicas=2`) la escritura se confirma sin la tercera.

## 4. Restablece la zona

```bash
kubectl uncordon <worker-de-zona-c>
```

El operador reprograma el broker en su nodo, se reincorpora al clúster y se
pone al día con las réplicas que se perdió. Verifica que vuelva a `Running`:

```bash
kubectl get pods -n meridiano-pagos | grep pagos-brokers
```

## Por qué funciona

`min.insync.replicas=2` es la pieza clave: define el mínimo de réplicas en
sincronía para confirmar una escritura. Con RF=3 repartido en 3 zonas, perder
una deja 2 en sincronía, que es exactamente el mínimo. Si bajara a 1 (dos zonas
caídas), las escrituras se rechazarían para no arriesgar la durabilidad: el
clúster prefiere frenar antes que perder un pago.
