# Guía 3 — Conectarse desde fuera (debut de kcat)

Por primera vez en el curso, vamos a hablar con el clúster **desde tu terminal**,
no desde un pod. Como `app-pagos`, una aplicación del banco.

## Extrae las credenciales a tu máquina

Una aplicación externa necesita dos cosas para una conexión TLS+SCRAM: la **CA
del clúster** (para confiar en el broker) y su **contraseña** SCRAM. Un script
las deja en un directorio local (ignorado por git):

```bash
bash bin/01-extraer-credenciales.sh
```

Deja en `./credenciales/`: `ca.crt`, `app-pagos.password` (y los de motor-fraude
para la guía 4). **Nunca** se versionan.

## Primer contacto: metadata

Antes de producir, confirma que kcat llega y se autentica, pidiendo metadata
(`-L`) al bootstrap externo `127.0.0.1:32000`:

```bash
kcat -b 127.0.0.1:32000 \
  -X security.protocol=SASL_SSL \
  -X sasl.mechanisms=SCRAM-SHA-512 \
  -X sasl.username=app-pagos \
  -X sasl.password="$(cat credenciales/app-pagos.password)" \
  -X ssl.ca.location=credenciales/ca.crt \
  -L
```

```text
Salida esperada (puede variar levemente)
Metadata for all topics (from broker -1: ...):
 3 brokers:
  broker 0 at 127.0.0.1:32001
  broker 1 at 127.0.0.1:32002
  broker 2 at 127.0.0.1:32003
 1 topics:
  topic "pagos.meridiano.transacciones" with 3 partitions ...
```

Fíjate: los brokers se anuncian como `127.0.0.1:3200x`, las direcciones del
puente que vimos en la guía 2. kcat las usará para conectar a cada broker.

> `app-pagos` solo ve el tópico de transacciones: su ACL le permite describir
> ese, y nada más. El mínimo privilegio del Lab 03 sigue vigente, también desde
> fuera.

## El primer mensaje del banco, desde fuera

Produce (`-P`). Escribe una línea y cierra con `Ctrl-D`:

```bash
kcat -b 127.0.0.1:32000 \
  -X security.protocol=SASL_SSL \
  -X sasl.mechanisms=SCRAM-SHA-512 \
  -X sasl.username=app-pagos \
  -X sasl.password="$(cat credenciales/app-pagos.password)" \
  -X ssl.ca.location=credenciales/ca.crt \
  -t pagos.meridiano.transacciones -P
```

```text
{"id":"TX-EXT-0001","origen":"app-externa","monto":42000}
```

Si no hay error, el mensaje entró. Acabas de producir el **primer pago de
Meridiano desde fuera del clúster**, por una puerta cifrada y autenticada. La
puerta funciona.

En la siguiente guía lo **leemos** de vuelta, pero por la otra puerta: la de
mTLS, como `motor-fraude`.
