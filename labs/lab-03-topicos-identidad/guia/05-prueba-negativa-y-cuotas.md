# Guía 5 — La prueba negativa y las cuotas

> Seguridad que no se verifica **en su rechazo** no está verificada. No basta con
> que lo permitido funcione: hay que comprobar que lo prohibido **falla**.

## 1. motor-fraude intenta producir → debe ser rechazado

`motor-fraude` solo tiene Read. Si intenta **producir**, la autorización debe
frenarlo:

```bash
kubectl exec -i cliente-kafka -n meridiano-pagos -- bash -c \
  'echo "intento-no-autorizado" | bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9093 \
   --command-config /props/motor-fraude.properties \
   --topic pagos.meridiano.transacciones'
```

```text
Salida esperada (puede variar levemente)
ERROR ... TopicAuthorizationException: Not authorized to access topics: [pagos.meridiano.transacciones]
```

Rechazado: `motor-fraude` no tiene **Write** sobre el tópico. La identidad es
válida (el certificado es bueno), pero el permiso no existe.

## 2. app-pagos intenta consumir → debe ser rechazado

`app-pagos` solo tiene Write. Si intenta **consumir**, también debe fallar:

```bash
kubectl exec cliente-kafka -n meridiano-pagos -- bash -c \
  'bin/kafka-console-consumer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --command-config /props/app-pagos.properties \
   --topic pagos.meridiano.transacciones --group intento \
   --from-beginning --timeout-ms 10000'
```

```text
Salida esperada (puede variar levemente)
ERROR ... GroupAuthorizationException: Not authorized to access group: intento
```

Rechazado de nuevo: `app-pagos` no tiene permiso de **Read** sobre ese consumer
group (ni sobre el tópico). Solo sabe producir.

> **Distingue dos errores que parecen iguales pero no lo son:**
> - `AuthenticationException`: "no sé quién eres" (credencial mala o ausente).
> - `AuthorizationException`: "sé quién eres, pero no puedes hacer eso" (falta una ACL).
>
> Aquí estamos viendo el segundo: la identidad es válida, el permiso no existe.

## 3. Cuotas: poner un techo a app-pagos

`app-pagos` lleva una cuota de producción baja (`producerByteRate: 102400`, unos
100 KiB/s por broker). Sirve para que un cliente no acapare el clúster. Veámosla
actuar produciendo un lote y observando el **throttling**.

Genera un lote de mensajes y míralo con métricas del productor:

```bash
kubectl exec cliente-kafka -n meridiano-pagos -- bash -c \
  'for i in $(seq 1 20000); do echo "relleno-de-cuota-mensaje-numero-$i"; done | \
   bin/kafka-console-producer.sh \
   --bootstrap-server pagos-kafka-bootstrap:9094 \
   --command-config /props/app-pagos.properties \
   --topic pagos.meridiano.transacciones'
```

Con la cuota baja, el broker **frena** (throttle) al productor: el envío tarda
más de lo que tardaría sin límite. La cuota está haciendo su trabajo: el productor
no puede pasar de su techo. Puedes confirmar la cuota declarada:

```bash
kubectl get kafkauser app-pagos -n meridiano-pagos -o jsonpath='{.spec.quotas}'; echo
```

## Verificación final del lab

```bash
bash bin/90-test-lab.sh
```

Todas las verificaciones en verde: tópicos gestionados, clúster endurecido,
usuarios con ACLs, round-trip autenticado, prueba negativa y cuota.

## Desafío extra (post-sesión): rotar la credencial de app-pagos

Una buena práctica de seguridad es **rotar credenciales** periódicamente, sin
cortar el servicio. El reto: regenerar la contraseña SCRAM de `app-pagos`
mientras un productor sigue trabajando, y reconectar con la nueva sin perder
mensajes. La resolución paso a paso —incluido el mecanismo exacto que ofrece el
User Operator en 0.51— está en `soluciones/desafio-rotacion.md`.

## Cierre

La plataforma de pagos dejó de ser un clúster abierto: tópicos con dueño y rastro,
identidades con nombre y apellido, permisos que dicen "sí" a lo justo y "no" a
todo lo demás. En el Lab 04 abrimos la puerta al exterior… con cerradura.
