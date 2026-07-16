# Guía 5 — Cerrar la puerta vieja

> El acto final del capítulo. En el Lab 03, la autorización dejó el listener plano
> 9092 **inservible** (ANONYMOUS sin permisos), pero la puerta seguía ahí. Hoy la
> **quitamos**: la puerta deja de existir.

## Elimina el listener plano del CR

En tu copia del `Kafka`, borra por completo el bloque del listener `plain`:

**ANTES**:

```yaml
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        ...
```

**DESPUÉS**:

```yaml
    listeners:
      - name: tls
        ...
```

La solución **final** ya no lo tiene. Aplícala: es el mismo clúster de la guía 02,
ahora sin la puerta vieja (el único cambio respecto a la parte 1 es que desaparece
el listener `plain`):

```bash
kubectl apply -n meridiano-pagos -f soluciones/parte-2-sin-plano/20-kafka-puerta-segura.yaml
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

## Verificación doble

### (a) Los clientes autenticados siguen funcionando

Nada de lo que construimos se rompe: el round-trip externo (SCRAM + mTLS) sigue
igual.

```bash
bash bin/90-test-lab.sh
```

### (b) La puerta vieja ya no responde

Intenta hablar con el puerto plano 9092 desde dentro del clúster, como antes:

```bash
kubectl run cli-9092 --rm -i --restart=Never -n meridiano-pagos \
  --image=quay.io/strimzi/kafka:0.51.0-kafka-4.2.0 --command -- \
  bin/kafka-broker-api-versions.sh --bootstrap-server pagos-kafka-bootstrap:9092
```

```text
Salida esperada (puede variar levemente)
java.lang.RuntimeException: Request METADATA failed on brokers [pagos-kafka-bootstrap:9092 (id: -1 ...)]
```

La conexión al puerto 9092 **falla por conexión**: ya no hay ningún listener
escuchando ahí. No es un "no tienes permiso" (el `TopicAuthorizationException`
del Lab 03): es un "aquí ya no hay puerta".

## La moraleja del capítulo

Compara los dos fallos del puerto 9092:

| | Lab 03 (puerta abierta) | Lab 04 (puerta quitada) |
|--|--|--|
| Estado del listener | Existe, pero authorization deniega | No existe |
| Tipo de fallo | **Autorización** (`TopicAuthorizationException`) | **Conexión** (`Connection refused`) |
| Metáfora | "Te dejo entrar al edificio, pero no a esta sala" | "Esta puerta ya no está en el muro" |

Esa diferencia es la lección: **autorización** es paso denegado en una puerta que
existe; **conexión rechazada** es una puerta que ya no existe. Defensa en
profundidad: primero cerramos con permisos (Lab 03), luego quitamos la puerta
(Lab 04).

## Cierre del Capítulo 3

Con esto, el mapa del curso enciende el Capítulo 3 completo: tópicos como código,
identidades con permisos mínimos, y una puerta al exterior que cifra, autentica y
no deja resquicios. Esto ya se parece a un sistema que **un auditor firma**.

## Desafío extra (post-sesión)

Inspecciona el certificado que presenta el broker en el puerto externo con
`openssl s_client` y lee su cadena (CN, SANs, emisor = la CA del clúster). La
resolución está en `soluciones/desafio-openssl.md`.
