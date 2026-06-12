# Guía 5 — Los ojos

> Parte 2, sesión 11. No se opera lo que no se ve. La plataforma gana ojos:
> métricas, Prometheus que las recoge, Grafana que las muestra.

## Habilitar métricas en `pagos`

Kafka puede exponer cientos de métricas vía JMX. El **JMX Prometheus Exporter**
las publica en un puerto HTTP (9404) que Prometheus puede leer. Strimzi trae un
ConfigMap oficial con la configuración del exporter.

Aplica el ConfigMap de métricas y el CR de `pagos` con `metricsConfig`:

```bash
kubectl apply -f infra/observabilidad/kafka-metrics-configmap.yaml
kubectl apply -f soluciones/observabilidad/00-kafka-pagos-metrics.yaml
```

El bloque que se añade al CR:

```yaml
  kafka:
    metricsConfig:
      type: jmxPrometheusExporter
      valueFrom:
        configMapKeyRef:
          name: kafka-metrics
          key: kafka-metrics-config.yml
```

El operador hace **otro rolling update** (ya es rutina para ti) para añadir el
exporter a cada broker. Espera:

```bash
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

## Desplegar Prometheus y Grafana

```bash
bash bin/01-desplegar-observabilidad.sh
```

Esto despliega un **Prometheus** que descubre los pods de Kafka y recoge sus
métricas del puerto 9404, y un **Grafana** con el datasource y el dashboard
oficial de Strimzi ya aprovisionados.

> **Nota de honestidad:** los ejemplos oficiales de Strimzi usan el **Prometheus
> Operator** (con PodMonitor). Aquí usamos un **Prometheus standalone**, más
> liviano, por el presupuesto de 16 GB. La **exposición** de métricas es la
> oficial (el ConfigMap del exporter); solo cambia cómo se recogen.

## Acceder a las UIs: port-forward

En un clúster real no expones Prometheus ni Grafana a Internet: accedes por un
túnel. `kubectl port-forward` ES esa forma. En **dos terminales**:

```bash
# Terminal A
kubectl port-forward -n meridiano-observabilidad svc/prometheus 9090:9090
# abre http://localhost:9090
```

```bash
# Terminal B
kubectl port-forward -n meridiano-observabilidad svc/grafana 3000:3000
# abre http://localhost:3000   (acceso anónimo de solo lectura)
```

En Prometheus, ve a **Status → Targets**: verás los pods de `pagos` con estado
`up`. Prometheus ya está recogiendo las métricas. En la siguiente guía las
leemos en Grafana.
