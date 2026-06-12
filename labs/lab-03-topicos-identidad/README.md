# Lab 03 — Tópicos como código e identidad

La plataforma de pagos deja de ser un clúster abierto. En la parte 1, los
tópicos pasan de crearse "a mano a las 3 AM" a declararse como código, con dueño
y rastro. En la parte 2, el clúster se endurece: identidades con nombre y
apellido, autenticación, y permisos de mínimo privilegio.

## Objetivos del lab

- Adoptar un tópico existente como `KafkaTopic` y crear otro nativo como código.
- Ver la reconciliación y la reversión del *drift*, y la convivencia con tópicos no gestionados.
- Endurecer el clúster con listeners autenticados (mTLS y SCRAM) y `authorization: simple`.
- Crear `KafkaUser` con ACLs de mínimo privilegio y cuotas; producir y consumir autenticado.
- Verificar la seguridad **en su rechazo** (pruebas negativas).

## Prerrequisitos

- **Lab 02 completado** (clúster `pagos` persistente con rack y el tópico de transacciones). Si no, recupéralo con `labs/lab-02-cluster-pagos/bin/95-recuperar-lab.sh`.
- Verifica con: `bash bin/00-verificar-prerrequisitos.sh`.

## Tiempo estimado

Dos bloques de 40 minutos (parte 1 = guías 1–2; parte 2 = guías 3–5).

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-adopcion-del-topico.md` | Adoptas el tópico existente y creas otro nativo como código. |
| 2 | `guia/02-reconciliacion-y-drift.md` | Ves la reconciliación, la reversión del drift y la convivencia. |
| 3 | `guia/03-endurecimiento.md` | Añades listeners autenticados y authorization; observas el rolling. |
| 4 | `guia/04-usuarios-y-acls.md` | Creas usuarios con ACLs, inspeccionas Secrets, produces/consumes autenticado. |
| 5 | `guia/05-prueba-negativa-y-cuotas.md` | Verificas los rechazos y las cuotas; lanzas el desafío de rotación. |

## Verifica tu trabajo

```bash
bash bin/90-test-lab.sh
```

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero (Lab 01 → 02 → 03), ejecuta la demo de drift de verdad y limpia.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 03 para un alumno rezagado.

## Nota sobre el listener plano

Tras el endurecimiento (parte 2), `authorization: simple` deniega a los clientes
sin autenticar (ANONYMOUS). El listener plano 9092 se conserva en este lab pero
queda inservible de facto; su cierre formal es el Lab 04. Por eso, desde la guía
04, todo cliente se autentica.
