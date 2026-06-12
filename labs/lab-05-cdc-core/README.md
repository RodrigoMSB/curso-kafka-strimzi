# Lab 05 — CDC del core

El corazón legado de Banco Meridiano (un PostgreSQL con la tabla de clientes)
entra al río de eventos: cada INSERT/UPDATE/DELETE del core se convierte en un
evento Kafka, **sin tocar el código del core**. CDC (Change Data Capture) con
Kafka Connect y Debezium es el puente entre el banco viejo y la plataforma nueva.

## Objetivos del lab

- Entender CDC (integrar el core sin doble escritura) y la anatomía `KafkaConnect` + `KafkaConnector`.
- Desplegar el core PostgreSQL preparado para CDC (`wal_level=logical`, `REPLICA IDENTITY FULL`, usuario de replicación).
- Construir la imagen de Connect con Debezium dentro del clúster (`spec.build`) y empujarla a un registry local.
- Capturar la tabla con un `KafkaConnector` y ver INSERT/UPDATE/DELETE como eventos en vivo.
- Operar el conector: pausar, sobrevivir a la caída del core, recuperarse.

## Prerrequisitos

- **Lab 04 completado**. Si no, recupéralo con `labs/lab-04-puerta-segura/bin/95-recuperar-lab.sh`.
- **Registry local**: créalo con `bash bin/01-registry-local.sh` (idempotente).
- Conexión a Internet (el build descarga la base de Connect y el plugin de Debezium).
- Verifica con: `bash bin/00-verificar-prerrequisitos.sh`.

> **Aviso importante:** el `spec.build` de Connect **construye una imagen dentro
> del clúster la primera vez** (descarga + construcción + push al registry). Esto
> **tarda varios minutos**. Es lo normal de este lab; la guía 3 te dice qué mirar
> mientras.

## Tiempo estimado

Un bloque de 40 minutos (guías 1–5). El build añade unos minutos de espera.

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-cdc-y-anatomia.md` | Entiendes CDC y la anatomía declarativa de Connect. |
| 2 | `guia/02-el-core-del-banco.md` | Despliegas el core PostgreSQL preparado para CDC. |
| 3 | `guia/03-equipo-connect.md` | Construyes la imagen de Connect con Debezium (build). |
| 4 | `guia/04-el-encargo-kafkaconnector.md` | Das el encargo y ves el CDC en vivo (op/before/after). |
| 5 | `guia/05-operar-el-conector.md` | Pausas, simulas la caída del core y ves la recuperación. |

## Verifica tu trabajo

```bash
bash bin/90-test-lab.sh
```

(El check insignia hace un round-trip CDC real: INSERT en PostgreSQL → evento en `core.public.clientes`.)

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero (Lab 01 → 05) **con build real**: es la corrida más larga del curso. Limpia el clúster y el registry al final. No corras dos e2e a la vez.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 05 para un alumno rezagado.
