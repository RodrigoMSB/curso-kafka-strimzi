# Guía 4 — Usuarios, ACLs y credenciales

Ahora que el clúster exige autenticación y autorización, creamos las identidades
del banco: cada aplicación con su nombre y sus permisos mínimos.

## Dos usuarios, dos mecanismos

- **`app-pagos`** — el productor. Autenticación **SCRAM-SHA-512** (usuario y
  contraseña). Permisos: solo **Write** y **Describe** sobre el tópico de
  transacciones. Nada más.
- **`motor-fraude`** — el consumidor del motor de detección de fraude.
  Autenticación **mTLS** (certificado de cliente). Permisos: **Read** y
  **Describe** sobre transacciones, y **Read** sobre su consumer group
  `fraude.deteccion`. Nada más.

Cada permiso responde a una pregunta: *¿qué necesita esta aplicación para hacer
su trabajo, y nada más?* Eso es **mínimo privilegio**.

## Completa el KafkaUser de app-pagos

Copia la plantilla a **tu** archivo de trabajo y complétala (no edites la
plantilla):

```bash
cp plantillas/30-kafkauser-app-pagos.yaml mi-app-pagos.yaml
```

**ANTES**:

```yaml
spec:
  authentication:
    type: # TODO A
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: pagos.meridiano.transacciones
          patternType: literal
        operations:
          - # TODO B
        host: "*"
```

**DESPUÉS**:

```yaml
spec:
  authentication:
    type: scram-sha-512
  authorization:
    type: simple
    acls:
      - resource:
          type: topic
          name: pagos.meridiano.transacciones
          patternType: literal
        operations:
          - Describe
          - Write
        host: "*"
```

Aplica **tu** manifiesto de `app-pagos`. El segundo usuario, `motor-fraude`, no
tiene plantilla —es una identidad de referencia con certificado de cliente—, así
que ese lo tomas de las soluciones:

```bash
kubectl apply -n meridiano-pagos -f mi-app-pagos.yaml
kubectl apply -n meridiano-pagos -f soluciones/users/31-motor-fraude.yaml
```

> Si tu `app-pagos` queda `NotReady`, compáralo con la referencia
> `soluciones/users/30-app-pagos.yaml` (compara, no copies) y corrige tu copia.
> Las `soluciones/` son la referencia; el camino es **tu** manifiesto.

```bash
kubectl get kafkausers -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME           CLUSTER   AUTHENTICATION   AUTHORIZATION   READY
app-pagos      pagos     scram-sha-512    simple          True
motor-fraude   pagos     tls              simple          True
```

## Los Secrets: así se entregan las credenciales

El User Operator no te manda la contraseña por chat: crea un **Secret** por
usuario. Las aplicaciones lo montan; nadie copia credenciales a mano.

```bash
kubectl get secret app-pagos motor-fraude pagos-cluster-ca-cert -n meridiano-pagos
```

- **`app-pagos`** — credenciales SCRAM (clave `password` y `sasl.jaas.config`).
- **`motor-fraude`** — certificado de cliente (`user.crt`, `user.key`, `user.p12`
  y su contraseña `user.password`).
- **`pagos-cluster-ca-cert`** — el certificado de la CA del clúster, para que el
  cliente confíe en los brokers (`ca.crt`, `ca.p12`, `ca.password`).

Mira, por ejemplo, qué claves trae el Secret de motor-fraude (sin imprimir los
valores):

```bash
kubectl get secret motor-fraude -n meridiano-pagos -o jsonpath='{.data}' | tr ',' '\n'
```

## Prepara el cliente (plomería)

Armar a mano los archivos de propiedades (extraer contraseñas de los Secrets,
escribir el `sasl.jaas.config`, apuntar a los keystores) es repetitivo y no
pedagógico. Lo hace un script por ti:

```bash
bash bin/01-preparar-cliente.sh
```

Esto deja un pod `cliente-kafka` con dos perfiles montados en `/props`:

- `/props/app-pagos.properties` — SCRAM, hacia el listener 9094.
- `/props/motor-fraude.properties` — mTLS, hacia el listener 9093.

## Produce autenticado como app-pagos

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'echo "{\"id\":\"TX-0002\",\"via\":\"autenticada\"}" | bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --command-config /props/app-pagos.properties \
   --topic pagos.meridiano.transacciones'
```

## Consume autenticado como motor-fraude

```bash
kubectl exec cliente-kafka -n meridiano-pagos -- bash -c \
  'bin/kafka-console-consumer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9093 \
   --command-config /props/motor-fraude.properties \
   --topic pagos.meridiano.transacciones --group fraude.deteccion \
   --from-beginning --timeout-ms 15000'
```

Verás el mensaje que produjo `app-pagos`. Dos identidades distintas, dos
mecanismos distintos, ambos funcionando con permisos mínimos. En la siguiente
guía comprobamos que esos permisos **también dicen que no**.
