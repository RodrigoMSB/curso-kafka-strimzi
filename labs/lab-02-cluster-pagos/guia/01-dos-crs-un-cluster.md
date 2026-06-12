# Guía 1 — Dos CRs para un clúster

En el Lab 01 contratamos al operador y lo dejamos vigilando `meridiano-pagos`,
vacío. Hoy le damos su primer encargo: el clúster Kafka de pagos. Para hacerlo
le hablamos en su idioma, los Custom Resources que inspeccionamos en el Lab 01.

## El reparto: `Kafka` + `KafkaNodePool`

Un clúster de Meridiano se declara con **dos tipos de recurso**:

- **`Kafka`** — describe el clúster como un todo: la versión de Kafka, los
  listeners (puertas de entrada), la configuración común y los operadores de
  entidad (Topic y User Operator). No dice cuántos nodos hay ni qué disco usan:
  eso es trabajo del otro recurso.
- **`KafkaNodePool`** — describe un **grupo de nodos** con un rol, un número de
  réplicas, sus recursos (CPU/memoria), su JVM y su almacenamiento. Un clúster
  puede tener varios pools, y cada pool evoluciona por separado.

Esta separación es deliberada: la forma del clúster (cuántos brokers, qué disco)
vive en los pools, y se puede cambiar sin tocar la identidad del clúster.

## Los dos pools de pagos

Declararemos dos pools:

- **`controllers`** — rol `controller`. En modo KRaft, los controllers
  mantienen los metadatos del clúster (quién es quién, qué particiones existen).
  Le ponemos **1 réplica**.
- **`brokers`** — rol `broker`. Los brokers guardan y sirven los datos: los
  mensajes de pagos. Le ponemos **3 réplicas**.

### Por qué 1 controller (y la honestidad que toca)

En **producción, el quorum de controllers es 3** y no se negocia: tres
controllers toleran la caída de uno sin perder el plano de control. Eso lo viste
en la teoría de la sesión 4.

Aquí usamos **1 solo controller** por una razón práctica y honesta: una VM de
16 GB no es un datacenter. Un quorum de 3 controllers más 3 brokers no cabe con
holgura en un laboratorio. Bajamos el controller a 1 **a sabiendas**, para que el
clúster quepa y el foco esté en aprender. No es lo que harías en el banco.

### Por qué 3 brokers

Tres brokers no son un capricho: son el mínimo para lo que viene.

- El tópico de pagos usará **replication factor 3**: cada partición vive en tres
  brokers, así que perder uno no pierde datos.
- En la parte 2 colocaremos **una réplica por zona**: tres brokers, tres zonas.

## KRaft y node pools, sin ceremonia

En el Lab 01 viste que Strimzi 0.51 sirve la API `v1`. En esta versión, KRaft y
los node pools son el **modo por defecto**: no hacen falta anotaciones especiales
en el CR para activarlos. Declaras `Kafka` + `KafkaNodePool` y listo.

> Cada `KafkaNodePool` se vincula a su `Kafka` con la etiqueta
> `strimzi.io/cluster: pagos`. Es la cuerda que ata el pool al clúster; sin ella,
> el operador no sabe a qué clúster pertenece el pool.

En la siguiente guía completas las plantillas y ves al operador convertir estas
declaraciones en pods reales.
