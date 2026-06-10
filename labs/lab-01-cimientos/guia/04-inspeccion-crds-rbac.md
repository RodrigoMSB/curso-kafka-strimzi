# Guía 4 — Inspección de los CRDs y el RBAC del operador

Al instalarse, el operador hizo dos cosas que vamos a inspeccionar: enseñó al
clúster un **vocabulario nuevo** (los CRDs) y reclamó un conjunto de **permisos**
(el RBAC). Entender ambos es entender cómo trabaja el operador.

## Parte A — Los CRDs: el vocabulario nuevo

Un **CRD** (Custom Resource Definition) le enseña a Kubernetes un tipo de objeto
que no traía de fábrica. Antes de Strimzi, el clúster no sabía qué era un
"Kafka"; ahora sí. Lista los que instaló Strimzi:

```bash
kubectl get crds | grep strimzi
```

```text
Salida esperada (puede variar levemente)
kafkabridges.kafka.strimzi.io
kafkaconnectors.kafka.strimzi.io
kafkaconnects.kafka.strimzi.io
kafkamirrormaker2s.kafka.strimzi.io
kafkanodepools.kafka.strimzi.io
kafkarebalances.kafka.strimzi.io
kafkas.kafka.strimzi.io
kafkatopics.kafka.strimzi.io
kafkausers.kafka.strimzi.io
```

Los principales, en una línea cada uno:

- **kafkas** — el clúster Kafka en sí. El recurso central.
- **kafkanodepools** — grupos de nodos (brokers/controllers) del clúster.
- **kafkatopics** — tópicos gestionados de forma declarativa.
- **kafkausers** — usuarios y sus permisos/credenciales.
- **kafkaconnects** — clústeres de Kafka Connect.
- **kafkaconnectors** — conectores concretos dentro de un Kafka Connect.
- **kafkamirrormaker2s** — replicación entre clústeres con MirrorMaker 2.
- **kafkabridges** — el puente HTTP hacia Kafka.
- **kafkarebalances** — solicitudes de rebalanceo de particiones (Cruise Control).

Explora el vocabulario sin salir de la terminal. `kubectl explain` describe los
campos de un recurso:

```bash
kubectl explain kafka.spec --recursive=false
```

Esto te muestra, a primer nivel, qué campos acepta el `spec` de un `Kafka`. Es
tu diccionario integrado: cuando dudes qué campo existe, pregúntale al clúster.

### El dato 2026: la API v1

Comprueba qué versiones de API sirve el CRD de `kafkas`:

```bash
kubectl get crd kafkas.kafka.strimzi.io -o jsonpath='{.spec.versions[*].name}'
```

```text
Salida esperada (puede variar levemente)
v1beta2 v1
```

Strimzi 0.51 introduce la **API `v1`** para todos los Custom Resources. En esta
versión las APIs previas (como `v1beta2`) siguen estando servidas, de modo que
nada se rompe durante la transición. A partir de Strimzi 1.0.0 solo existirá
`v1`. Conocer esto te evita sorpresas al escribir manifiestos en el Lab 02.

## Parte B — El RBAC: los permisos del operador

Para administrar Kafka, el operador necesita permisos. Veamos su identidad y
sus roles.

Su identidad (ServiceAccount) en la oficina del administrador:

```bash
kubectl get serviceaccount -n meridiano-sistema
```

```text
Salida esperada (puede variar levemente)
NAME                       SECRETS   AGE
default                    0         5m
strimzi-cluster-operator   0         3m
```

Los roles a nivel de clúster que definió Strimzi:

```bash
kubectl get clusterroles | grep strimzi
```

```text
Salida esperada (puede variar levemente)
strimzi-cluster-operator-global
strimzi-cluster-operator-leader-election
strimzi-cluster-operator-namespaced
strimzi-cluster-operator-watched
strimzi-entity-operator
strimzi-kafka-broker
strimzi-kafka-client
```

Y cómo se conectan esos roles con la ServiceAccount (los bindings):

```bash
kubectl get rolebindings,clusterrolebindings -A | grep strimzi
```

```text
Salida esperada (puede variar levemente)
NAMESPACE           NAME                                      ROLE
meridiano-pagos     strimzi-cluster-operator-watched          ClusterRole/strimzi-cluster-operator-watched
meridiano-sistema   strimzi-cluster-operator                  ClusterRole/strimzi-cluster-operator-namespaced
...                 strimzi-cluster-operator                  ClusterRole/strimzi-cluster-operator-global
```

### Pregunta guiada

**¿Por qué el operador necesita permisos en `meridiano-pagos` si está instalado
en `meridiano-sistema`?**

Porque su **scope de vigilancia** se configuró hacia ese namespace mediante los
values (`watchNamespaces: [meridiano-pagos]`). Para poder crear y administrar
allí los recursos de Kafka cuando se lo pidamos, el operador recibe —vía un
RoleBinding en `meridiano-pagos`— los permisos sobre ese namespace. Vive en un
sitio y actúa sobre otro: exactamente la separación de gobernanza de la Guía 1.
