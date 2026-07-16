# Guía 2 — Abrir la puerta (nodeport TLS)

Vamos a añadir al CR dos listeners externos de tipo `nodeport`. Trabaja sobre tu
copia del `Kafka` del Lab 03 (la endurecida).

## Completa los listeners externos

Los TODO de `plantillas/20-listener-externo.yaml` (listener de aplicaciones):

**ANTES**:

```yaml
    - name: extscram
      port: 9095
      type: # TODO A
      tls: # TODO B
      authentication:
        type: # TODO C
      configuration:
        bootstrap:
          nodePort: 32000
        brokers:
          - { broker: 0, nodePort: 32001, advertisedHost: 127.0.0.1, advertisedPort: 32001 }
          ...
```

**DESPUÉS**:

```yaml
    - name: extscram
      port: 9095
      type: nodeport
      tls: true
      authentication:
        type: scram-sha-512
      configuration:
        bootstrap:
          nodePort: 32000
        brokers:
          - { broker: 0, nodePort: 32001, advertisedHost: 127.0.0.1, advertisedPort: 32001 }
          ...
```

El segundo listener (`extmtls`, mTLS) es igual pero con `authentication.type: tls`
y los puertos 32004–32007. Aplica el CR completo (la solución de esta parte trae
todo):

```bash
kubectl apply -n meridiano-pagos -f soluciones/parte-1-con-plano/20-kafka-puerta-segura.yaml
```

> **La puerta vieja sigue abierta.** Esta solución **conserva** el listener plano
> 9092 heredado del Lab 03 (inservible de facto por `authorization`, pero
> presente en el muro). Abrir las puertas nuevas no cierra la vieja: cerrarla es
> el acto final de la guía 05.

> El `port` del CR (9095, 9096) es el puerto **interno** en el que el broker
> escucha; los **nodePorts** (32000–32007) son los puertos **externos**, los que
> tu host alcanza. No los confundas.

## Por qué `advertisedHost: 127.0.0.1` (el diagrama de capas)

Cuando un cliente se conecta al **bootstrap**, Kafka le responde con la lista de
brokers y **la dirección por la que debe contactar a cada uno**. Esa dirección es
la *advertised address*. Si el broker anunciara su IP interna del clúster, tu
host no sabría llegar. Por eso la fijamos a la dirección que tu host sí alcanza:

```
  tu terminal (host)
        │  127.0.0.1:3200x
        ▼
  mapeo de Docker (kind-config: hostPort -> containerPort)
        ▼
  NodePort del nodo control-plane (32000-32007)
        ▼
  Service de Strimzi  ->  el broker correcto
```

Cada broker anuncia `127.0.0.1:<su nodePort>`, que viaja por ese puente hasta él.

> **En EKS esto es distinto:** los brokers anuncian las direcciones **reales**
> que el NLB les asigna; no se fija `127.0.0.1`. El `127.0.0.1` es un artificio
> del laboratorio local. Lo verás en la guía 4.

## Observa el rolling y el status

El operador reinicia los brokers de a uno para abrir las nuevas puertas:

```bash
kubectl get pods -n meridiano-pagos -w
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

Cuando termine, el propio CR publica las direcciones de cada listener en su
`status`:

```bash
kubectl get kafka pagos -n meridiano-pagos \
  -o jsonpath='{range .status.listeners[*]}{.name}{" -> "}{.bootstrapServers}{"\n"}{end}'
```

```text
Salida esperada (puede variar levemente)
tls -> pagos-kafka-bootstrap.meridiano-pagos.svc:9093
scram -> pagos-kafka-bootstrap.meridiano-pagos.svc:9094
extscram -> 127.0.0.1:32000
extmtls -> 127.0.0.1:32004
```

Las dos puertas externas están abiertas, cada una en su bootstrap. En la
siguiente guía cruzamos una desde tu terminal.
