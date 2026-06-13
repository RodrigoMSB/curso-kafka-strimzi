# Pistas graduadas

Tres niveles. **Destapa solo el que necesites** — el capstone se trata de que tú
diseñes. Ya conoces las herramientas (MM2, KafkaUser/ACLs, KafkaTopic,
observabilidad, rolling). Aquí solo orientamos.

---

## Nivel 1 — Qué piezas necesitas

Para migrar `legado.transferencias` del Kafka legado a la plataforma sin perder
mensajes, vas a necesitar **cinco** piezas:

1. **El tópico destino como código.** Declara `legado.transferencias` en `pagos`
   como `KafkaTopic`. Pregúntate qué **factor de replicación** corresponde al
   migrar a una plataforma de 3 brokers (no copies la pobreza del legado).
2. **El espejo.** Un `KafkaMirrorMaker2` que lea del legado y escriba en `pagos`.
   Recuerda el Lab 06… pero fíjate en qué lado está ahora autenticado.
3. **La identidad del espejo en el destino.** En el Lab 06 el target era abierto.
   Aquí el target (pagos) está endurecido: MM2 necesitará una identidad capaz de
   **crear y escribir** en el destino.
4. **La identidad del negocio nuevo.** Tras el cutover, ¿quién escribe en la
   plataforma? Decídelo (y justifícalo en el runbook).
5. **El runbook.** Orden, punto de no retorno, rollback antes del cutover.

Herramientas de apoyo (plomería provista): `bin/01-desplegar-legado.sh`,
`bin/02-cutover-productor.sh`, `bin/03-decomisar-legado.sh`. Y el evaluador
`bin/90-test-lab.sh` te dice exactamente qué falta.

---

## Nivel 2 — Los campos clave del MM2 y la identidad target

**La inversión respecto al Lab 06** (esto es lo que más confunde):

- En el Lab 06, **pagos era el ORIGEN** (autenticado) y `dr` el destino (abierto).
  El usuario `mm2` solo necesitaba **leer**.
- Aquí, **el legado es el ORIGEN** (PLAINTEXT, sin auth — "así vivíamos") y
  **pagos es el DESTINO** (endurecido). Por eso:
  - El bloque `source` del MM2 **no lleva** `authentication` ni `tls`.
  - El bloque `target` **sí** autentica (SCRAM) contra el listener interno
    `pagos-kafka-bootstrap:9094`.
  - Connect guarda sus tópicos internos (`configs`/`offsets`/`status`) en el
    **target**, así que la identidad del target necesita ACLs de
    **`Create`, `Write`, `Describe`, `Read`, `AlterConfigs`** sobre tópicos, más
    `Read`/`Describe` de grupos y operación de `cluster`. (En el Lab 06 esas ACLs
    eran de solo lectura: aquí no alcanzan.)

**Nombres y resolución:** el legado es un contenedor en la red de kind,
alcanzable por su nombre `kafka-legado:9092` (igual que el registry del Lab 05).

**IdentityReplicationPolicy:** consérvala (como en el Lab 06) para que
`legado.transferencias` no se renombre en el destino — así el productor nuevo
escribe al mismo nombre tras el cutover.

**La identidad nueva del negocio:** lo correcto en un banco es una identidad
**dedicada y de mínimo privilegio** (`Write`/`Describe` solo sobre el tópico), no
reutilizar `app-pagos` (su ACL es para otro tópico) ni la amplia de MM2.

---

## Nivel 3 — Casi-solución

Si te atascaste, la plantilla `plantillas/30-mirrormaker2-migracion.yaml` tiene
los TODO marcados. Las respuestas:

- **target.alias:** `pagos`; **source.alias:** `legado`.
- **source.bootstrapServers:** `kafka-legado:9092` (sin auth).
- **target.authentication:** `scram-sha-512`, `username: mm2-migracion`,
  `passwordSecret: { secretName: mm2-migracion, password: password }`.
- **replication.policy.class:**
  `org.apache.kafka.connect.mirror.IdentityReplicationPolicy`.
- **topicsPattern:** `"legado\\..*"`.

ACLs del usuario `mm2-migracion` (target), por recurso:
- `topic "*"`: `Create, Describe, DescribeConfigs, Read, Write, Alter, AlterConfigs`
- `group "*"`: `Read, Describe`
- `cluster`: `Describe, DescribeConfigs, Create, IdempotentWrite, Alter, AlterConfigs`

Usuario `transferencias` (productor nuevo), mínimo privilegio:
- `topic legado.transferencias` (literal): `Describe, Write`

Cutover:
```bash
bin/02-cutover-productor.sh --usuario transferencias
```
(El script registra el último ID del legado y arranca el productor nuevo desde
último+1 con `"origen":"plataforma"`.)

La solución completa está en `soluciones/`. Úsala para comparar, no para copiar:
el `90` mide tu estado final, no de quién es el YAML.
