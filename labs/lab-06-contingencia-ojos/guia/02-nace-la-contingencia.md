# Guía 2 — Nace la contingencia

Desplegamos el clúster `dr`. Antes, un paso de gobernanza: el operador no lo
vigila todavía.

## Ampliar el scope del operador (gobernanza, no plomería)

El operador se instaló (Lab 01) vigilando **solo** `meridiano-pagos`. El DR vive
en `meridiano-dr`, un namespace nuevo. Para que el operador lo administre, hay
que **ampliar su scope** explícitamente. Esto NO es plomería oculta: es una
decisión de gobernanza (quién puede crear clústeres y dónde), y la haces tú.

Crea el namespace y amplía el `watchNamespaces` del operador con `helm upgrade`:

```bash
kubectl apply -f soluciones/dr/10-namespace.yaml

helm upgrade strimzi-operator strimzi/strimzi-kafka-operator --version 0.51.0 \
  -n meridiano-sistema --reuse-values \
  --set 'watchNamespaces={meridiano-pagos,meridiano-dr}'

kubectl rollout status deployment/strimzi-cluster-operator -n meridiano-sistema
```

El operador se reinicia con el scope ampliado y crea, en `meridiano-dr`, los
permisos (RBAC) que necesita para administrar allí. Ahora sí vigila el DR.

## Desplegar el clúster `dr`

Sobre una copia de `plantillas/20-kafka-dr.yaml`, completa los TODO:

**ANTES** (la plantilla trae **tres** TODO: réplicas, roles y el tipo de storage):

```yaml
spec:
  replicas: # TODO A
  roles:
    - # TODO B
    - # TODO B
  ...
  storage:
    type: jbod
    volumes:
      - id: 0
        type: # TODO C
        kraftMetadata: shared
```

**DESPUÉS**:

```yaml
spec:
  replicas: 1
  roles:
    - controller
    - broker
  ...
  storage:
    type: jbod
    volumes:
      - id: 0
        type: ephemeral
        kraftMetadata: shared
```

Un **único nodo dual-role** (controller + broker), storage **efímero**, RF=1. No
olvides el TODO C del `storage`: sin él, el `KafkaNodePool` es inválido
(`storage.volumes[0].type: Required value`).

> **Honestidad de laboratorio:** el DR real vive en **otra región**, con varios
> nodos y discos persistentes reales. Este es el **modelo a escala**: cabe en
> 16 GB junto a todo lo demás, y sirve para entender la mecánica de la réplica.

```bash
kubectl apply -n meridiano-dr -f mi-dr.yaml
kubectl wait --for=condition=Ready kafka/dr -n meridiano-dr --timeout=600s
```

```bash
kubectl get kafka dr -n meridiano-dr
kubectl get pods -n meridiano-dr
```

```text
Salida esperada (puede variar levemente)
NAME   DESIRED KAFKA REPLICAS   READY
dr     1                        True
```

El clúster de contingencia existe, vacío. En la siguiente guía tendemos el
espejo que lo va a llenar.
