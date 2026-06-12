# Guía 1 — CDC y la anatomía de Connect

El corazón de Banco Meridiano sigue siendo un viejo PostgreSQL: la base de datos
del core, con la tabla de clientes. No lo vamos a reescribir —nadie reescribe el
core de un banco a la ligera— pero sí queremos que **cada cambio en él se
convierta en un evento Kafka**, en tiempo real, sin tocar una línea de su código.
Eso es **CDC** (Change Data Capture).

## El anti-patrón que evitamos

La tentación sería: "que la aplicación del core escriba en la base **y** publique
en Kafka". Eso es **doble escritura**, y es una trampa: si la base se confirma y
Kafka falla (o al revés), los dos sistemas quedan inconsistentes, y reconciliar
eso en un banco es una pesadilla.

CDC evita la trampa leyendo el **registro de transacciones (WAL)** de PostgreSQL:
la base ya escribe ahí todo lo que pasa. Debezium lee ese registro y publica los
cambios. **Una sola escritura** (la de siempre, en la base), y los eventos salen
de un hecho ya consumado. Sin doble escritura, sin inconsistencias.

## La anatomía declarativa

Igual que con tópicos (Lab 03) y usuarios, en Meridiano el CDC se declara como
código, con dos Custom Resources:

- **`KafkaConnect`** — el **equipo de trabajo**: un clúster de Kafka Connect.
  Strimzi incluso **construye su imagen** (base de Connect + el plugin de
  Debezium) dentro del clúster. Es infraestructura: existe una vez, lo usan
  muchos conectores.
- **`KafkaConnector`** — el **encargo** concreto: "captura la tabla
  `public.clientes` del core con Debezium". Es declarativo, con historia en Git,
  como todo lo demás del curso.

```
   PostgreSQL (core)  --WAL-->  Debezium (en Kafka Connect)  -->  tópico core.public.clientes
        ^                              ^                                  ^
   no se toca                el equipo (KafkaConnect)            el encargo (KafkaConnector)
```

## Lo que viene

1. Desplegamos el core PostgreSQL (guía 2).
2. Construimos el equipo de Connect con Debezium (guía 3) — **ojo: el build tarda
   varios minutos la primera vez**.
3. Damos el encargo y vemos el CDC en vivo (guía 4).
4. Operamos el conector: pausa, caída del core, recuperación (guía 5).

Antes de empezar, verifica los prerrequisitos (Lab 04 completo y el registry
local):

```bash
bash bin/01-registry-local.sh   # crea el registry local (idempotente)
bash bin/00-verificar-prerrequisitos.sh
```
