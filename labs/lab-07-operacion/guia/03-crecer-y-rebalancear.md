# Guía 3 — Crecer y rebalancear

El plato fuerte: agregamos un broker y movemos carga hacia él, con propuesta y
aprobación.

## 1. Crecer: escalar a 4 brokers

Sobre una copia de `plantillas/05-nodepool-brokers-escalar.yaml`, completa el TODO:

**ANTES**: `replicas: # TODO`  **DESPUÉS**: `replicas: 4`

```bash
kubectl apply -n meridiano-pagos -f mi-brokers.yaml
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s

# Espera a que el broker NUEVO esté 1/1 y registrado, no solo el CR en Ready:
kubectl wait --for=condition=Ready pod/pagos-brokers-4 -n meridiano-pagos --timeout=300s
```

> **Por qué esa segunda espera.** Cruise Control toma una **foto** del clúster
> cuando arranca el rebalanceo. Si aplicas el `KafkaRebalance` (paso 2) antes de
> que `pagos-brokers-4` esté realmente listo y registrado, el broker 4 no aparece
> en la foto y el rebalance queda `NotReady` con
> `IllegalArgumentException: Some/all brokers specified don't exist` — y **no se
> recupera solo** (hay que borrarlo y volver a crearlo). El `kafka/pagos` en
> `Ready` no garantiza que el broker nuevo ya esté arriba; por eso esperamos al
> pod, no solo al CR.

El broker nuevo es `pagos-brokers-4`. Comprueba que **nació vacío** (ninguna
partición vive ahí). Mira el tópico de transacciones desde el pod cliente:

```bash
kubectl exec cliente-kafka -n meridiano-pagos -- bash -c \
  'bin/kafka-topics.sh --bootstrap-server pagos-kafka-bootstrap:9094 \
   --command-config /props/app-pagos.properties --describe --topic pagos.meridiano.transacciones' 2>/dev/null \
  | grep Replicas
```

En las líneas `Replicas:` solo aparecen los brokers 0, 1, 2 — **nunca el 4**.
Agregar un broker no movió nada.

## 2. La orden de trabajo: KafkaRebalance add-brokers

Sobre una copia de `plantillas/10-kafkarebalance.yaml`, completa los TODO:

**ANTES**:

```yaml
spec:
  mode: # TODO A
  brokers: # TODO B
```

**DESPUÉS**:

```yaml
spec:
  mode: add-brokers
  brokers: [4]
```

```bash
kubectl apply -n meridiano-pagos -f mi-rebalance.yaml
```

## 3. Leer la propuesta

Cruise Control genera una **propuesta** (puede tardar un par de minutos: necesita
su ventana de métricas). El estado del `KafkaRebalance` lo dice:

```bash
kubectl get kafkarebalance agregar-broker-4 -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME              CLUSTER   ...   STATUS
agregar-broker-4  pagos           ProposalReady
```

Cuando llegue a `ProposalReady`, **lee qué piensa mover** (en el status):

```bash
kubectl get kafkarebalance agregar-broker-4 -n meridiano-pagos -o jsonpath='{.status.optimizationResult}' | tr ',' '\n'
```

Verás cuántas réplicas va a mover, a qué brokers, y el tamaño de los datos. Nada
se ha movido todavía.

## 4. Aprobar y observar

Nada se mueve sin tu aprobación explícita, con la annotation:

```bash
kubectl annotate kafkarebalance agregar-broker-4 -n meridiano-pagos strimzi.io/rebalance=approve
```

El estado pasa a `Rebalancing` y luego a `Ready` cuando termina:

```bash
kubectl get kafkarebalance agregar-broker-4 -n meridiano-pagos -w
```

## 5. Verificar que el broker 4 ya tiene particiones

Repite el `--describe` del paso 1:

```text
Salida esperada (puede variar levemente)
  Partition: 0  ... Replicas: 2,0,4  ...    <- ¡ahora aparece el 4!
```

El broker 4 ya carga su parte. **Y nada se movió sin una propuesta legible y una
aprobación explícita** — eso es operación de banco. En la siguiente guía hacemos
el camino inverso con la misma disciplina.
