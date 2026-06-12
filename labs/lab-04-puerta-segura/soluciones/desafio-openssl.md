# Desafío extra — inspeccionar el certificado del broker con openssl

> Objetivo: ver con tus ojos el certificado que el broker presenta en la puerta
> externa, y comprobar que lo firma la CA del clúster.

## 1. Pide el certificado al broker

`openssl s_client` abre una conexión TLS y muestra lo que el servidor presenta.
Conéctate a un broker externo (por ejemplo el del puerto 32001, broker 0 del
listener SCRAM) usando la CA del clúster como ancla de confianza:

```bash
openssl s_client -connect 127.0.0.1:32001 \
  -CAfile credenciales/ca.crt </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
```

```text
Salida esperada (puede variar levemente)
subject=O=io.strimzi, CN=pagos-kafka-...
issuer=O=io.strimzi, CN=cluster-ca v0
X509v3 Subject Alternative Name:
    DNS:pagos-kafka-bootstrap, DNS:pagos-kafka-bootstrap.meridiano-pagos.svc, ...,
    IP Address:127.0.0.1
```

## 2. Lee la cadena

- **`subject` (CN)** — la identidad del broker.
- **`issuer`** — quién lo firmó: la **cluster CA** de Strimzi (`cluster-ca`). Es
  la misma CA que extrajiste a `ca.crt`; por eso tu cliente confía en el broker.
- **`subjectAltName` (SANs)** — los nombres y direcciones por los que el
  certificado es válido. Entre ellos aparece `127.0.0.1`: por eso la conexión por
  el puente local supera la verificación de hostname.

## 3. Verifica la cadena completa

Pide a openssl que valide la cadena contra la CA:

```bash
openssl s_client -connect 127.0.0.1:32001 -CAfile credenciales/ca.crt </dev/null 2>/dev/null \
  | grep -E "Verify return code"
```

```text
Salida esperada
    Verify return code: 0 (ok)
```

`0 (ok)` significa que la cadena es válida: el broker presenta un certificado
firmado por una CA en la que confías, válido para la dirección por la que te
conectaste. Eso es exactamente lo que comprueba kcat (y cualquier cliente serio)
antes de enviar un solo byte de un pago.
