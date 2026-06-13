# Guía 2 — Encender Cruise Control

Cruise Control se enciende añadiendo un bloque al CR `Kafka` de `pagos`.

## El bloque `cruiseControl`

Sobre tu copia del `Kafka` de `pagos` (el del Lab 06, con métricas), añade:

```yaml
spec:
  # ... kafka, entityOperator ...
  cruiseControl:
    resources:
      requests: { cpu: 200m, memory: 512Mi }
      limits: { cpu: "1", memory: 1Gi }
    jvmOptions:
      -Xms: 384m
      -Xmx: 384m
```

La solución (`soluciones/cruise-control/00-kafka-pagos-cc.yaml`) trae el CR
completo. Aplícalo:

```bash
kubectl apply -n meridiano-pagos -f soluciones/cruise-control/00-kafka-pagos-cc.yaml
kubectl wait --for=condition=Ready kafka/pagos -n meridiano-pagos --timeout=600s
```

El operador hace un rolling (ya es rutina) y despliega un **pod nuevo** de Cruise
Control:

```bash
kubectl get pods -n meridiano-pagos | grep cruise-control
```

```text
Salida esperada (puede variar levemente)
pagos-cruise-control-xxxxxxxxxx-xxxxx   2/2     Running   0   2m
```

> Cruise Control necesita una **ventana de métricas** para analizar el clúster
> antes de poder generar su primera propuesta. Si pides un rebalanceo recién
> encendido, la propuesta puede tardar un par de minutos en estar lista. Es
> normal; lo verás en la siguiente guía.

Cruise Control está observando el clúster. En la guía 3 le pedimos su primer
trabajo: rebalancear tras crecer.
