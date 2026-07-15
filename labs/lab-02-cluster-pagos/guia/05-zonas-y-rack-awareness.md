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

## 2. Habilita rack awareness en el clúster vivo

En la guía 4, cambiar el **storage** nos obligó a **destruir y recrear** el
clúster: hay decisiones que se toman el día cero y no se tocan en caliente. El
`rack` es lo contrario: se **añade sobre el clúster corriendo** y el operador lo
propaga sin downtime. Vamos a verlo con nuestros ojos.

En tu copia del `Kafka` (`mi-kafka.yaml`), completa el bloque `rack`
(TODO D de la plantilla):

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

Aplícalo **sobre el clúster que ya está corriendo** (no borras nada):

```bash
kubectl apply -n meridiano-pagos -f mi-kafka.yaml
```

El operador no destruye el clúster: hace un **rolling update**. Reinicia los
brokers **de a uno**, esperando que cada uno vuelva a estar sano antes de tocar
el siguiente, para inyectarles su zona sin cortar el servicio. Míralo en vivo:

```bash
kubectl get pods -n meridiano-pagos -w
```

Verás el patrón del rolling update: un broker pasa a `Terminating`, vuelve como
`Running`, y solo entonces le toca al siguiente. En ningún momento se caen los
tres a la vez: el clúster sigue sirviendo pagos mientras se actualiza. (Corta con
`Ctrl-C` cuando los tres estén `Running` otra vez.)

Espera a que termine y a que el clúster vuelva a Ready:

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

## La lección: dos cambios, dos caminos

Guarda esta comparación, porque es el corazón del Lab 02:

- El **storage** (guía 4) **no se cambia en caliente**. El operador ignora el
  cambio y avisa con un `Warning`; hubo que **destruir y recrear** el clúster
  para pasar a persistente.
- El **rack** (esta guía) **sí se cambia en caliente**. El operador lo aplicó
  **sobre el clúster vivo**, con un rolling update ordenado y sin downtime.

El mismo operador, dos respuestas opuestas, según lo que puede o no rehacerse sin
riesgo. Saber cuál es cuál —qué se decide el día cero y qué se ajusta con el
clúster corriendo— es lo que separa operar Kafka de solo instalarlo.

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
