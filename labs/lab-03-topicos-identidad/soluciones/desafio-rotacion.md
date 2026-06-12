# Desafío extra — rotar la credencial SCRAM de app-pagos

> Objetivo: cambiar la contraseña SCRAM de `app-pagos` de forma controlada, sin
> reescribir el usuario ni adivinar contraseñas generadas.

## El mecanismo: una contraseña gestionada por ti

Por defecto, el User Operator **genera** la contraseña de un usuario SCRAM (y la
deja en el Secret del usuario). Para poder **rotarla** de forma controlada, le
dices al operador que tome la contraseña de un Secret que tú controlas, con el
campo `spec.authentication.password.valueFrom`:

```yaml
spec:
  authentication:
    type: scram-sha-512
    password:
      valueFrom:
        secretKeyRef:
          name: app-pagos-password
          key: password
```

## Paso a paso

1. Crea el Secret con la contraseña inicial:

```bash
kubectl create secret generic app-pagos-password -n meridiano-pagos \
  --from-literal=password='ContraseniaInicial-v1'
```

2. Apunta el `KafkaUser` a ese Secret (añade el bloque `password.valueFrom` de
   arriba a `app-pagos` y aplícalo). El operador reconcilia: la credencial SCRAM
   en Kafka pasa a ser la del Secret, y el Secret del usuario (`app-pagos`) se
   regenera con el nuevo `sasl.jaas.config`.

3. **Rotación**: cambia el valor del Secret de origen:

```bash
kubectl create secret generic app-pagos-password -n meridiano-pagos \
  --from-literal=password='ContraseniaRotada-v2' \
  --dry-run=client -o yaml | kubectl apply -f -
```

   El User Operator detecta el cambio y actualiza la credencial SCRAM en Kafka y
   el Secret `app-pagos`.

## Sin cortar al productor en marcha

La clave para no cortar el servicio es que el productor lea su contraseña del
Secret `app-pagos` **montado** (no incrustada en la imagen). Al rotar:

1. Mientras el productor sigue con la credencial vieja, aplicas la rotación.
2. El operador actualiza la credencial en Kafka y el Secret montado.
3. El productor vuelve a leer el Secret (recarga del montaje) y reconecta con la
   nueva en su siguiente sesión, sin reiniciar el pod.

Verifica que la nueva contraseña funciona y la vieja ya no, regenerando los
properties con `bin/01-preparar-cliente.sh` y produciendo un mensaje. La rotación
quedó hecha sin tocar el `KafkaUser` ni reescribir las ACLs.
