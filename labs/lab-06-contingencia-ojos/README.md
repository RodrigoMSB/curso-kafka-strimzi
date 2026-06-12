# Lab 06 — Contingencia y ojos

Dos historias en un lab. **Parte 1:** un banco no puede perder los pagos si se
cae un datacenter — nace el clúster de contingencia `dr` y MirrorMaker 2 replica
el río de eventos hacia él. **Parte 2:** no se opera lo que no se ve — la
plataforma gana ojos con Prometheus y Grafana.

## Objetivos del lab

- Entender RPO/RTO y la anatomía de MirrorMaker 2 (activo/pasivo).
- Desplegar un clúster `dr` económico y ampliar el scope del operador (gobernanza).
- Replicar los tópicos de negocio con MM2 (IdentityReplicationPolicy) y ver la réplica en vivo.
- Habilitar métricas en Kafka y desplegar Prometheus + Grafana.
- Leer la plataforma: las 4 métricas que un administrador de banco mira primero.

## Prerrequisitos

- **Lab 05 completado**. Si no, recupéralo con `labs/lab-05-cdc-core/bin/95-recuperar-lab.sh`.
- Verifica con: `bash bin/00-verificar-prerrequisitos.sh`.

> **⚠️ Advertencia de recursos (16 GB justos):** este es el lab **más pesado del
> curso**. Sobre la cadena 01→05 completa, agrega un segundo clúster Kafka (DR),
> MirrorMaker 2, Prometheus y Grafana. **Cierra aplicaciones pesadas** (navegadores
> con muchas pestañas, otros IDEs) antes de empezar. Si ves pods en `Pending` o
> `OOMKilled`, es memoria: ver `docs/troubleshooting.md`.

## Tiempo estimado

Dos bloques de 40 minutos (parte 1 = guías 1–4; parte 2 = guías 5–6).

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-rpo-rto-y-mm2.md` | Entiendes RPO/RTO y la anatomía de MM2. |
| 2 | `guia/02-nace-la-contingencia.md` | Amplías el scope del operador y despliegas el `dr`. |
| 3 | `guia/03-el-espejo.md` | Tiendes MirrorMaker 2 (identidad + replication policy). |
| 4 | `guia/04-el-simulacro.md` | Produces en `pagos` y lees la réplica en `dr`. |
| 5 | `guia/05-los-ojos.md` | Habilitas métricas y despliegas Prometheus + Grafana. |
| 6 | `guia/06-leer-la-plataforma.md` | Lees el dashboard y las 4 métricas clave. |

## Verifica tu trabajo

```bash
bash bin/90-test-lab.sh
```

(Checks insignia: round-trip de réplica `pagos`→`dr` y una métrica de Kafka viva en Prometheus.)

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero (Lab 01 → 06): es la **corrida total del curso** y reporta el **pico de memoria** del Docker VM. Limpia clúster + registry al final.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 06 para un alumno rezagado.
