# Desafío extra (parte 1) — leer los goals de un rebalanceo

> Objetivo: entender qué optimiza Cruise Control cuando genera una propuesta.

## Mira la propuesta y sus goals

```bash
kubectl get kafkarebalance agregar-broker-4 -n meridiano-pagos -o yaml | sed -n '/status:/,$p'
```

En el `status` verás `optimizationResult` (qué va a mover) y, si lo consultas en
los logs/estado de Cruise Control, la lista de **goals** que usó. Cruise Control
trae un conjunto de goals por defecto, ordenados por prioridad. Tres de los más
importantes:

## 1. `ReplicaCapacityGoal` (capacidad de réplicas)

Asegura que **ningún broker tenga más réplicas de las que puede manejar**. Es un
*hard goal*: si un broker está sobrecargado de particiones, la propuesta moverá
réplicas para descongestionarlo. Evita que un broker se convierta en cuello de
botella por acumular demasiadas particiones.

## 2. `ReplicaDistributionGoal` (distribución de réplicas)

Busca que **el número de réplicas esté repartido de forma pareja** entre los
brokers. Es el goal que hace que un broker recién agregado **reciba su parte**:
sin él, el broker nuevo se quedaría casi vacío. Es el corazón de "rebalancear
tras crecer".

## 3. `DiskUsageDistributionGoal` (distribución de disco)

Equilibra el **uso de disco** entre los brokers. Dos brokers pueden tener el
mismo número de réplicas pero muy distinto volumen de datos (unas particiones
pesan más que otras). Este goal mira los bytes, no solo el conteo, para que
ningún disco se llene antes que los demás.

## La idea

Una propuesta de Cruise Control no es "mover cosas al azar": es la solución a un
problema de optimización con **objetivos jerárquicos**. Por eso es segura
aprobarla — y por eso un banco la lee antes de aprobar: para saber, exactamente,
qué criterios se están aplicando a sus datos.
