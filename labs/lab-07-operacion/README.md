# Lab 07 — Operación

La plataforma ya existe, está segura, integrada, con contingencia y ojos. Este
capítulo es la **vida adulta**: operarla. **Parte 1:** crecer sin downtime
(escalar + rebalancear con Cruise Control). **Parte 2:** cambiar sin downtime
(rolling updates, upgrade del DR) y sobrevivir al mantenimiento de la
infraestructura (Drain Cleaner).

## Objetivos del lab

- Entender por qué agregar un broker no redistribuye nada, y cómo Cruise Control lo resuelve con propuesta + aprobación.
- Crecer (3→4 brokers) y rebalancear con `KafkaRebalance` (add-brokers), y encoger (remove-brokers → 3).
- Consolidar los rolling updates y disparar un rolling manual.
- Ensayar un upgrade de versión (4.1.1 → 4.2.0) sobre el DR, como en producción.
- Entender Drain Cleaner y por qué el mantenimiento de nodos no debe atropellar a Kafka.

## Prerrequisitos

- **Lab 06 completado**. Si no, recupéralo con `labs/lab-06-contingencia-ojos/bin/95-recuperar-lab.sh`.
- Verifica con: `bash bin/00-verificar-prerrequisitos.sh`.

> **Recursos:** este lab agrega Cruise Control (un pod) y, durante el ejercicio,
> un 4º broker temporal. Sobre la carga del Lab 06 sigue cabiendo en 16 GB, pero
> mantén cerradas las apps pesadas.

## Tiempo estimado

Dos bloques de 40 minutos (parte 1 = guías 1–4; parte 2 = guías 5–7).

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-el-problema-del-crecimiento.md` | Entiendes el crecimiento y la anatomía de Cruise Control. |
| 2 | `guia/02-encender-cruise-control.md` | Habilitas Cruise Control en `pagos`. |
| 3 | `guia/03-crecer-y-rebalancear.md` | Escalas a 4, rebalanceas con propuesta + aprobación. |
| 4 | `guia/04-encoger-con-disciplina.md` | Vacías el broker 4 y encoges a 3 sin perder datos. |
| 5 | `guia/05-rolling-como-rutina.md` | Consolidas los rolling y disparas uno manual. |
| 6 | `guia/06-upgrade-sobre-el-dr.md` | Ensayas el upgrade 4.1.1 → 4.2.0 sobre el DR. |
| 7 | `guia/07-drain-cleaner.md` | Entiendes Drain Cleaner (conceptual + referencia). |

## Estado final canónico

- Pool de **brokers en 3** (los labs siguientes y el capstone asumen 3).
- **Cruise Control** habilitado en `pagos`.
- **DR en Kafka 4.2.0** (tras el upgrade).

## Verifica tu trabajo

```bash
bash bin/90-test-lab.sh
```

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero (Lab 01 → 07): la **corrida final del curso**. Ejecuta el ciclo completo add-brokers→aprobar→remove-brokers→aprobar y reporta el pico de memoria. Limpia clúster + registry al final.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 07 para un alumno rezagado.
