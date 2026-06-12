# Guía 3 — El equipo de Connect (con identidad propia)

Kafka Connect necesita dos cosas: una **identidad** en el clúster (su KafkaUser
con ACLs) y una **imagen** que incluya el plugin de Debezium. Strimzi construye
esa imagen por nosotros.

## La identidad de Connect

Como todo cliente de Meridiano, Connect se autentica y tiene permisos mínimos.
Sobre una copia de `plantillas/20-kafkauser-connect.yaml`, completa los prefijos
de las ACLs:

**ANTES**:

```yaml
      - resource:
          type: topic
          name: # TODO A   (prefijo de los tópicos internos de Connect)
          patternType: prefix
```

**DESPUÉS**:

```yaml
      - resource:
          type: topic
          name: connect-cdc
          patternType: prefix
```

Connect necesita: sus **tópicos internos** (configs/offsets/status, prefijo
`connect-cdc`), su **consumer group** (prefijo `connect-cdc`), **escribir** en
los tópicos de CDC (prefijo `core.`) y `IdempotentWrite` a nivel de cluster
(su productor es idempotente). La solución trae todo resuelto.

## La credencial de la base, sin texto plano

El conector necesitará la contraseña del usuario `debezium`. **No** la ponemos en
el `KafkaConnector` en claro: la guardamos en un Secret (`connect-db-cred`) que el
pod de Connect **monta como archivo**, y un *config provider* la lee en tiempo de
ejecución. Lo verás en la guía 4.

## El build: Strimzi construye la imagen

Aplica los usuarios y el `KafkaConnect`:

```bash
kubectl apply -n meridiano-pagos -f soluciones/connect/10-connect-db-cred.yaml
kubectl apply -n meridiano-pagos -f soluciones/connect/20-kafkauser-connect.yaml
kubectl apply -n meridiano-pagos -f soluciones/connect/25-kafkauser-cdc-reader.yaml
kubectl apply -n meridiano-pagos -f soluciones/connect/30-kafkaconnect.yaml
```

El `spec.build` del `KafkaConnect` le dice a Strimzi: toma la base de Connect,
añade el plugin de Debezium PostgreSQL (un `.tar.gz` de Maven Central, con su
checksum) y **empuja la imagen al registry local**.

> **El build tarda varios minutos la primera vez** (descarga + construcción +
> push). Es normal. Mira el pod de build mientras tanto:
>
> ```bash
> kubectl get pods -n meridiano-pagos -w        # aparece connect-cdc-connect-build
> kubectl logs -f connect-cdc-connect-build -n meridiano-pagos
> ```

El push usa `additionalBuildOptions: [--insecure]` porque el registry local
sirve por HTTP sin TLS. **Es legítimo solo porque el registry es de juguete**; en
EKS con ECR (HTTPS), esa opción desaparece.

Espera a que el equipo esté listo:

```bash
kubectl wait --for=condition=Ready kafkaconnect/connect-cdc -n meridiano-pagos --timeout=900s
```

Cuando termine, la imagen está en el registry y el pod de Connect corre con
Debezium dentro. En la siguiente guía le damos el encargo.
