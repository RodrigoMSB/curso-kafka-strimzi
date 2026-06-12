# Guía 1 — RPO, RTO y la anatomía de MirrorMaker 2

Un banco no puede perder los pagos si se cae un datacenter. Pero "no perder
nada, nunca" cuesta infinito. Así que se ponen números.

## Dos preguntas de banco

- **RPO (Recovery Point Objective):** ¿cuántos datos puedes perder? Se mide en
  tiempo: "como mucho, los últimos 5 segundos de pagos". Un RPO de 0 (cero
  pérdida) exige replicación **síncrona**, que es cara y lenta.
- **RTO (Recovery Time Objective):** ¿cuánto puedes estar caído? "Como mucho 2
  minutos hasta que el sistema de respaldo tome el control".

Nuestra topología es **activo/pasivo**: el clúster `pagos` (activo) atiende
todo; el clúster `dr` (pasivo, de contingencia) recibe una copia replicada de
forma **asíncrona**. Asíncrona significa **RPO > 0**: el DR va unos instantes por
detrás. Es el trade-off que un banco acepta a cambio de no frenar cada pago
esperando al otro datacenter.

## La anatomía de MirrorMaker 2

MM2 es Kafka Connect especializado en replicar entre clústeres. Corre como un
conjunto de conectores:

- **MirrorSourceConnector** — lee los tópicos del origen (`pagos`) y los escribe
  en el destino (`dr`).
- **MirrorCheckpointConnector** — traduce los offsets de los consumidores entre
  clústeres (para que, tras un failover, un consumidor sepa por dónde seguir en
  el DR).
- **MirrorHeartbeatConnector** — emite latidos para medir la salud y el lag de la
  replicación.

```
   pagos (activo)              dr (contingencia)
   ┌──────────────┐   MM2     ┌──────────────┐
   │ pagos.*      │ ───────▶  │ pagos.*      │   (réplica asíncrona)
   │ core.*       │           │ core.*       │
   └──────────────┘           └──────────────┘
```

## Lo que viene

1. Nace el clúster `dr` (guía 2) — y ampliamos el scope del operador.
2. Tendemos el espejo con MM2 (guía 3).
3. Simulamos la contingencia: producimos en `pagos` y leemos del `dr` (guía 4).

Verifica los prerrequisitos (y vigila la memoria: este lab es el más pesado):

```bash
bash bin/00-verificar-prerrequisitos.sh
```
