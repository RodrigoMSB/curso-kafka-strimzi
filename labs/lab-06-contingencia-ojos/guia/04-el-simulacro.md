# Guía 4 — El simulacro

El espejo está tendido. Comprobemos que un pago producido en `pagos` aparece en
el `dr`.

## Produce en `pagos`, lee del `dr`

Produce una transacción en el clúster activo, como `app-pagos` (las ACLs del
Cap 3 siguen mandando — usamos el pod cliente del Lab 03):

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'echo "{\"id\":\"TX-DR-0001\",\"via\":\"simulacro\"}" | bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --command-config /props/app-pagos.properties \
   --topic pagos.meridiano.transacciones'
```

Ahora consume **del DR** (su listener es simple, sin autenticación):

```bash
kubectl run dr-cons --rm -i --restart=Never -n meridiano-dr \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-consumer.sh \
  --bootstrap-server dr-kafka-bootstrap.meridiano-dr.svc:9092 \
  --topic pagos.meridiano.transacciones --from-beginning --timeout-ms 20000
```

```text
Salida esperada (puede variar levemente)
{"id":"TX-DR-0001","via":"simulacro"}
```

El pago viajó de `pagos` a `dr`. Y fíjate: el tópico se llama **igual** en ambos
(`pagos.meridiano.transacciones`), gracias a `IdentityReplicationPolicy`.

## El lag de réplica (RPO en acción)

La réplica es **asíncrona**: el DR va por detrás. Ese retraso es el **RPO**. Si
produces muchos mensajes de golpe y consumes del DR de inmediato, puede que los
últimos aún no hayan llegado. Espera un momento y vuelve a consumir: aparecen.

> En un banco, este lag se **mide** (lo verás en Prometheus en la parte 2): si
> crece, tu RPO empeora — estás más expuesto a perder pagos en una caída.

## "Se cayó el datacenter"

En un failover real, los consumidores se **reapuntan** al DR y siguen leyendo la
historia de pagos desde ahí. No tiramos `pagos` abajo (sería muy disruptivo para
el resto de la cadena), pero el simulacro de arriba ya lo demuestra: **la
historia de pagos está en el DR, hasta el último offset replicado**.

### Cómo se traducen los offsets (lectura)

Cuando un consumidor se mueve al DR, ¿desde qué offset sigue? Los offsets de
`pagos` y `dr` no coinciden (son clústeres distintos). El **MirrorCheckpointConnector**
de MM2 publica periódicamente "checkpoints" que mapean los offsets de cada grupo
de consumidores entre origen y destino, junto con los **offset-syncs** que
relacionan las posiciones de los tópicos. Así, una herramienta de failover puede
traducir "el grupo X iba por el offset 1000 en pagos" a "eso es el offset 950 en
dr" y reanudar sin releer todo ni saltarse nada. (En este lab los dejamos
emitiéndose; su consumo en un failover real excede el tiempo de sala.)

## Desafío extra (parte 1)

Crea un tópico nuevo en `pagos` que calce con el patrón (p. ej.
`pagos.meridiano.alertas`) y verifica que MM2 lo **descubre y replica solo**
(refresco automático de tópicos). Resolución en `soluciones/desafio-topico-nuevo.md`.
