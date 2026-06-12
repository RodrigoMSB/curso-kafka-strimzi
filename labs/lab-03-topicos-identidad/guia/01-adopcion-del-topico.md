# Guía 1 — La adopción del tópico de las 3 AM

El tópico `pagos.meridiano.transacciones` existe desde el Lab 02. Lo creamos por
CLI, a mano, "a las 3 AM". Funciona, pero no tiene **dueño**, ni **historia**, ni
**control**: nadie sabe quién lo creó, con qué configuración, ni puede revisarlo
en un repositorio. Hoy le ponemos nombre y apellido: lo convertimos en código.

## Prerrequisito

```bash
bash bin/00-verificar-prerrequisitos.sh
```

Debe estar verde el estado del Lab 02. Si no, recupéralo con
`labs/lab-02-cluster-pagos/bin/95-recuperar-lab.sh`.

## El Topic Operator y la adopción

El Entity Operator del clúster incluye el **Topic Operator**. En Strimzi 0.51 es
**unidireccional**: el `KafkaTopic` es la fuente de verdad y el operador empuja
ese estado hacia Kafka. No va al revés.

Cuando declaras un `KafkaTopic` cuyo tópico **ya existe** en Kafka, el operador
lo **adopta**: lo toma bajo gestión sin recrearlo, siempre que la configuración
declarada sea compatible con la real (mismo nombre; las particiones no se pueden
reducir). Por eso la regla de oro de una adopción limpia es declarar, al
principio, **lo mismo que ya hay**.

## Trabaja sobre una copia

> **Las plantillas nunca se editan.** Copia y trabaja sobre la copia.

```bash
cp plantillas/10-transacciones-adopcion.yaml mi-transacciones.yaml
```

Completa los TODO con la configuración **real** del tópico (la que viste en el
Lab 02):

**ANTES** (plantilla):

```yaml
metadata:
  name: # TODO
spec:
  partitions: # TODO
  replicas: # TODO
```

**DESPUÉS**:

```yaml
metadata:
  name: pagos.meridiano.transacciones
spec:
  partitions: 3
  replicas: 3
```

Aplica:

```bash
kubectl apply -n meridiano-pagos -f mi-transacciones.yaml
```

Verifica la adopción: el `KafkaTopic` queda `Ready` y el tópico **no se recreó**
(sigue teniendo sus datos del Lab 02):

```bash
kubectl get kafkatopic pagos.meridiano.transacciones -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME                            CLUSTER   PARTITIONS   REPLICATION FACTOR   READY
pagos.meridiano.transacciones   pagos     3            3                    True
```

Si el `KafkaTopic` quedara `NotReady`, lee sus condiciones (`kubectl get
kafkatopic ... -o yaml`, sección `status.conditions`): el `message` te dirá qué
no cuadra (típicamente, una configuración declarada incompatible con la real).

## Segundo tópico, ahora nativo como código

El tópico de confirmaciones nace directamente como código: no existe en Kafka
hasta que el operador lo crea a partir del `KafkaTopic`.

```bash
kubectl apply -n meridiano-pagos -f soluciones/topics/11-confirmaciones.yaml
```

```bash
kubectl get kafkatopics -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME                            CLUSTER   PARTITIONS   REPLICATION FACTOR   READY
pagos.meridiano.confirmaciones  pagos     3            3                    True
pagos.meridiano.transacciones   pagos     3            3                    True
```

Dos tópicos de negocio, ambos declarados. En la siguiente guía vemos qué hace
el operador cuando la realidad y la declaración no coinciden.
