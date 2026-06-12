# Guía 3 — El endurecimiento del clúster

> Parte 2, sesión 7. Hasta aquí el clúster escucha en un listener plano, sin
> autenticación: cualquiera dentro de la red puede producir y consumir. Para un
> banco, eso es una puerta abierta. Vamos a poner cerraduras.

## Qué cambiamos

En el CR `Kafka` añadimos:

- Un listener **`tls`** (9093) con autenticación **mutua por certificado** (`tls`).
- Un listener **`scram`** (9094) con autenticación **usuario/contraseña** (`scram-sha-512`).
- **`authorization: simple`**: a partir de ahora, sin una ACL que lo permita, no
  se puede hacer nada.

El listener **plano 9092 se conserva** en este lab (su cierre formal es el acto
final del Lab 04). Pero, como verás, la autorización lo deja **inservible de
facto**.

## Completa los listeners

Sobre tu copia del `Kafka` (la del Lab 02), aplica el bloque endurecido. Los TODO
de la plantilla `plantillas/20-listeners-endurecidos.yaml`:

**ANTES**:

```yaml
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: # TODO A
      - name: scram
        port: 9094
        type: internal
        tls: false
        authentication:
          type: # TODO B
    authorization:
      type: simple
```

**DESPUÉS**:

```yaml
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls
      - name: scram
        port: 9094
        type: internal
        tls: false
        authentication:
          type: scram-sha-512
    authorization:
      type: simple
```

Aplica el CR completo (la solución reúne todo el `Kafka` endurecido):

```bash
kubectl apply -n meridiano-pagos -f soluciones/kafka/20-kafka-endurecido.yaml
```

## Observa el rolling update (esto es contenido)

El operador no reinicia los brokers de golpe: los reinicia **de a uno**, esperando
que cada uno vuelva sano antes de tocar el siguiente. Así el clúster nunca pierde
quórum ni deja de dar servicio. Míralo:

```bash
kubectl get pods -n meridiano-pagos -w
```

Verás `pagos-brokers-0`, luego `1`, luego `2` reiniciarse en secuencia. Espera a
que el clúster vuelva a Ready:

```bash
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

Eso es **mantenimiento sin downtime**: la promesa central de operar Kafka con un
operador.

## La puerta vieja se cerró sola

Con `authorization: simple`, todo cliente que no se autentique entra como usuario
**`ANONYMOUS`**, y ANONYMOUS no tiene ninguna ACL. Pruébalo: intenta consumir por
el listener plano, sin credenciales, como hacías en el Lab 02:

```bash
kubectl run cli-anon --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-console-consumer.sh --bootstrap-server pagos-kafka-bootstrap:9092 \
  --topic pagos.meridiano.transacciones --from-beginning --timeout-ms 10000
```

```text
Salida esperada (puede variar levemente)
ERROR ... TopicAuthorizationException: Not authorized to access topics: [pagos.meridiano.transacciones]
```

El consumo plano, sin credenciales, ahora **falla**: el cliente entró como
ANONYMOUS y no tiene ninguna ACL.

La lección: **la autorización cerró de facto la puerta vieja.** El listener plano
sigue abierto en el papel, pero sin permisos no sirve para nada. En el Lab 04 lo
cerramos también de jure. Por eso, de aquí en adelante, todo cliente se
autentica: es lo que hacemos en la siguiente guía.
