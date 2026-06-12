# Guía 4 — mTLS externo y la referencia de EKS

Cerramos el lazo: leemos desde fuera el mensaje que produjo `app-pagos`, pero por
la **otra** puerta, la de mTLS, como `motor-fraude`.

## mTLS: el cliente también presenta certificado

En SCRAM, el cliente prueba su identidad con una contraseña. En **mTLS** la
prueba con un **certificado de cliente**: el broker presenta el suyo (firmado por
la CA del clúster) y el cliente presenta el suyo (también firmado por la CA). Por
eso es *mutual* TLS. `bin/01-extraer-credenciales.sh` ya dejó el certificado y la
llave de `motor-fraude` en `./credenciales/`.

## Consume desde fuera por la puerta mTLS

El bootstrap del listener mTLS es `127.0.0.1:32004`. Consume (`-C`) desde el
principio (`-o beginning`) y sal al final (`-e`):

```bash
kcat -b 127.0.0.1:32004 \
  -X security.protocol=SSL \
  -X ssl.ca.location=credenciales/ca.crt \
  -X ssl.certificate.location=credenciales/motor-fraude.crt \
  -X ssl.key.location=credenciales/motor-fraude.key \
  -t pagos.meridiano.transacciones -C -e -o beginning
```

```text
Salida esperada (puede variar levemente)
{"id":"TX-EXT-0001","origen":"app-externa","monto":42000}
% Reached end of topic ...
```

Ahí está: el mensaje que `app-pagos` produjo por la puerta SCRAM, leído por
`motor-fraude` por la puerta mTLS. **Dos identidades, dos mecanismos, dos
puertas, un solo flujo de pagos** — y todo desde fuera del clúster.

> **No cruces las puertas:** si conectas con la contraseña SCRAM al bootstrap
> mTLS (32004), o con el certificado al bootstrap SCRAM (32000), la conexión
> falla. Cada puerta exige su mecanismo. Es un error clásico; el troubleshooting
> explica cómo se ve.

## Cómo se vería en producción: el manifiesto NLB

En kind usamos `nodeport` por necesidad. En EKS, el banco usaría un listener
`loadbalancer` que provisiona un **AWS Network Load Balancer**. Lee con calma el
manifiesto de referencia:

```bash
cat infra/referencia-eks-loadbalancer.yaml
```

Las claves del bloque:

- **`type: loadbalancer`** — Strimzi le pide a la nube un NLB por listener.
- Las **annotations** las interpreta el **AWS Load Balancer Controller**:
  - `aws-load-balancer-type: external` — activa ese controlador (no el proveedor in-tree, obsoleto).
  - `aws-load-balancer-nlb-target-type: ip` — el NLB enruta directo a los pods.
  - `aws-load-balancer-scheme: internet-facing` — accesible desde Internet (o `internal` para solo-VPC).
- **No hay `advertisedHost: 127.0.0.1`**: los brokers anuncian las direcciones
  reales que el NLB les asigna; el operador las descubre y las publica en el
  `status`.

Es el mismo concepto del laboratorio —una puerta externa autenticada y cifrada—
con la fontanería que la nube resuelve por ti. (Referencia: no se ejecuta en kind.)

En la última guía cerramos, para siempre, la puerta vieja.
