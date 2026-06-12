# Desafío extra (parte 2) — el lag de MM2 y el RPO

> Objetivo: encontrar en Prometheus la métrica de retraso de la replicación de
> MM2 y razonar su relación con el RPO.

## 1. La métrica del lag de réplica

MM2 expone, vía su propio exporter de métricas, el **replication lag**: cuánto va
por detrás el destino respecto del origen, por tópico/partición. En Prometheus
(o Grafana), busca métricas de MirrorMaker 2; las relevantes vienen del
MirrorSourceConnector, por ejemplo:

```text
kafka_connect_mirror_mirrorsourceconnector_replication_latency_ms_max
```

(También hay `record_age_ms` y series de `record_count` que indican el flujo de
la réplica.) Consúltala en Prometheus → Graph.

> Para que estas métricas aparezcan, el pod de MM2 debe exponer también el puerto
> `tcp-prometheus`; si en tu despliegue no las ves, habilita `metricsConfig` en el
> CR `KafkaMirrorMaker2` con un ConfigMap de exporter (como el de Kafka). El
> objetivo del desafío es razonar la relación, aunque la métrica exacta dependa de
> que MM2 exponga sus métricas.

## 2. La relación con el RPO

El **RPO** (cuántos datos puedes perder en una caída) es, en una réplica
asíncrona, **exactamente lo que el destino aún no recibió**. Eso es el **lag**:

- **Lag bajo y estable** → el DR está casi al día → RPO pequeño → en una caída de
  `pagos` pierdes muy pocos pagos (los de los últimos instantes).
- **Lag que crece** → el DR se queda atrás → RPO empeora → en una caída perderías
  **todo lo que MM2 no alcanzó a replicar**. Un lag que sube sin parar es una
  alarma: la replicación no da abasto (red saturada, MM2 con pocos recursos,
  destino lento).

Por eso los espejos también se observan: el lag de MM2 **es** tu RPO en vivo. Si
un banco se compromete a "RPO ≤ 5 segundos", esa métrica es la que tiene que
mirar —y alertar— para cumplirlo.
