# Guía 3 — El espejo (MirrorMaker 2)

MM2 se conecta a dos clústeres: lee del origen (`pagos`, autenticado) y escribe
en el destino (`dr`). Necesita una identidad en el origen.

## La identidad de MM2 en el origen

Aplica el `KafkaUser` `mm2` (SCRAM) en `meridiano-pagos`:

```bash
kubectl apply -n meridiano-pagos -f soluciones/mm2/10-kafkauser-mm2.yaml
```

> Las ACLs de MM2 son **amplias por naturaleza**: debe leer todos los tópicos
> que calcen con el patrón, descubrir tópicos y grupos, y operar su tópico
> interno de offset-syncs. En producción se acotan al patrón replicado; aquí
> priorizamos que el espejo funcione sin fricción. (El DR no necesita usuario:
> su listener es simple, sin autenticación.)

## El CR de MirrorMaker 2

Sobre una copia de `plantillas/30-mirrormaker2.yaml`, completa los TODO:

**ANTES**:

```yaml
  target:
    alias: # TODO A
  mirrors:
    - source:
        alias: # TODO B
      ...
      topicsPattern: # TODO C
```

**DESPUÉS**:

```yaml
  target:
    alias: dr
  mirrors:
    - source:
        alias: pagos
      ...
      topicsPattern: "pagos\\.meridiano\\..*|core\\..*"
```

- **`target` = dr** — el clúster sobre el que corre MM2 (donde escribe la copia).
- **`source` = pagos** — el clúster del que lee, autenticado como `mm2` (SCRAM).
- **`topicsPattern`** — solo los tópicos de negocio: `pagos.meridiano.*` y `core.*`.

### La decisión de nombres: IdentityReplicationPolicy

Por defecto, MM2 **renombra** los tópicos replicados con el alias del origen:
`pagos.meridiano.transacciones` se convertiría en `pagos.pagos.meridiano.transacciones`
en el DR. Para un DR activo/pasivo limpio queremos los **mismos nombres**, así
que usamos `IdentityReplicationPolicy`:

```yaml
replication.policy.class: org.apache.kafka.connect.mirror.IdentityReplicationPolicy
```

> **Trade-off:** identity exige **disciplina**: nunca replicar de vuelta del DR al
> origen, porque con nombres idénticos se formaría un **bucle** infinito. En
> activo/pasivo unidireccional es seguro y da nombres idénticos en el DR.

Aplica y espera:

```bash
kubectl apply -n meridiano-pagos -f mi-mm2.yaml
kubectl wait --for=condition=Ready kafkamirrormaker2/pagos-a-dr -n meridiano-pagos --timeout=600s
```

```bash
kubectl get kafkamirrormaker2 -n meridiano-pagos
```

```text
Salida esperada (puede variar levemente)
NAME         DESIRED REPLICAS   READY
pagos-a-dr   1                  True
```

El espejo está tendido. En la siguiente guía lo ponemos a prueba.
