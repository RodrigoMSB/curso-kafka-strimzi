# Guía 2 — Desplegar el clúster

## Antes de empezar: prerrequisitos

El Lab 02 parte del estado final del Lab 01 (operador vigilando) sobre el
clúster de 4 nodos del curso. Compruébalo:

```bash
bash bin/00-verificar-prerrequisitos.sh
```

Si falla, recupera el Lab 01 con `labs/lab-01-cimientos/bin/95-recuperar-lab.sh`.

## Trabaja sobre copias, nunca sobre las plantillas

> **Las plantillas nunca se editan.** Copia y trabaja sobre las copias. Si
> editaste una plantilla por error, restáurala con `git checkout -- plantillas/`.

```bash
cp plantillas/10-nodepool-controllers.yaml mis-controllers.yaml
cp plantillas/11-nodepool-brokers.yaml     mis-brokers.yaml
cp plantillas/20-kafka-pagos.yaml          mi-kafka.yaml
```

Estos `mis-*.yaml` son tuyos y no se versionan (están en el `.gitignore`).

## Completa los TODO de los pools

### Pool de controllers (`mis-controllers.yaml`)

**ANTES** (como viene la plantilla):

```yaml
spec:
  replicas: # TODO
  roles:
    - # TODO
```

**DESPUÉS** (resuelto):

```yaml
spec:
  replicas: 1
  roles:
    - controller
```

### Pool de brokers (`mis-brokers.yaml`)

**ANTES**:

```yaml
spec:
  replicas: # TODO
  roles:
    - # TODO
  ...
  storage:
    type: jbod
    volumes:
      - id: 0
        type: # TODO
        kraftMetadata: shared
```

**DESPUÉS**:

```yaml
spec:
  replicas: 3
  roles:
    - broker
  ...
  storage:
    type: jbod
    volumes:
      - id: 0
        type: ephemeral
        kraftMetadata: shared
```

El `Kafka` (`mi-kafka.yaml`) se aplica tal cual en esta parte: el bloque `rack`
sigue comentado, llegará en la guía 05.

### Verifica tus copias antes de aplicar

```bash
grep -E "replicas:|- (controller|broker)" mis-controllers.yaml mis-brokers.yaml
```

```text
Salida esperada (puede variar levemente)
mis-controllers.yaml:  replicas: 1
mis-controllers.yaml:    - controller
mis-brokers.yaml:  replicas: 3
mis-brokers.yaml:    - broker
```

## Aplica los tres recursos

```bash
kubectl apply -n meridiano-pagos -f mis-controllers.yaml
kubectl apply -n meridiano-pagos -f mis-brokers.yaml
kubectl apply -n meridiano-pagos -f mi-kafka.yaml
```

## Observa la convergencia

El operador acaba de recibir el encargo. Míralo trabajar.

Los pods que va creando:

```bash
kubectl get pods -n meridiano-pagos -w
```

```text
Salida esperada (puede variar levemente)
NAME                          READY   STATUS    RESTARTS   AGE
pagos-controllers-3           1/1     Running   0          90s
pagos-brokers-0               1/1     Running   0          80s
pagos-brokers-1               1/1     Running   0          80s
pagos-brokers-2               1/1     Running   0          80s
pagos-entity-operator-...     2/2     Running   0          40s
```

La primera vez, la imagen de Kafka tarda en descargarse; verás `ContainerCreating`
un rato. Es normal (corta con `Ctrl-C` cuando estén todos en `Running`).

El estado del clúster según su propio `.status`:

```bash
kubectl get kafka pagos -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME    DESIRED KAFKA REPLICAS   READY   WARNINGS
pagos   3                        True
```

La columna `READY` en `True` es el operador diciendo "encargo cumplido". Si
quieres el detalle, lee `kubectl get kafka pagos -n meridiano-pagos -o yaml` y
busca `status.conditions`.

Y el operador "razonando en voz alta", como en el Lab 01:

```bash
kubectl logs deployment/strimzi-cluster-operator -n meridiano-sistema | tail -20
```

Verás reconciliaciones del clúster `pagos`. El administrador que contratamos ya
está administrando. En la siguiente guía mandamos el primer mensaje.
