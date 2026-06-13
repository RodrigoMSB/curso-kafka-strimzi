# Guía 1 — El problema del crecimiento

La plataforma de Meridiano ya existe, está segura, integrada, con contingencia y
ojos. Este capítulo es la **vida adulta**: operarla. Crecer, cambiar y sobrevivir
al mantenimiento — todo **sin downtime**.

## Agregar un broker no redistribuye nada

Intuición equivocada: "si el clúster está lleno, agrego un broker y se descongas­
tiona solo". **Falso.** El broker nuevo nace **vacío**: las particiones viejas se
quedan exactamente donde estaban. El broker nuevo no recibe nada hasta que
**alguien mueve** particiones hacia él.

Mover particiones a mano (el *partition reassignment* manual) es posible pero
doloroso: calcular qué mover, a dónde, sin saturar la red ni dejar una partición
sub-replicada a mitad de camino. En un clúster de banco, hacerlo a ojo es pedir
un incidente.

## Cruise Control: el rebalanceo con criterio

**Cruise Control** automatiza esto. Analiza el clúster contra una lista de
**goals** (objetivos: equilibrio de réplicas, de líderes, de disco, de CPU…) y
genera una **propuesta** de movimientos. Tú la lees, la apruebas, y él la
ejecuta de forma controlada.

La anatomía declarativa, otra vez:

- **`cruiseControl`** en el CR `Kafka` — enciende el componente (un pod aparte).
- **`KafkaRebalance`** — una **orden de trabajo**: "rebalancea para estos brokers
  nuevos", "vacía estos brokers". Es un CR, con historia en Git.

```
   escalar (3 -> 4 brokers)        KafkaRebalance (add-brokers)
   el broker 4 nace VACÍO   --->   propuesta -> apruebas -> se mueven réplicas
```

> **El patrón de banco:** NADA se mueve sin una **propuesta legible** y una
> **aprobación explícita**. No hay magia automática sobre los datos de un banco.

## Lo que viene

1. Encendemos Cruise Control (guía 2).
2. Crecemos a 4 brokers y rebalanceamos con aprobación (guía 3).
3. Encogemos de vuelta a 3 con la misma disciplina (guía 4).

Verifica el prerrequisito:

```bash
bash bin/00-verificar-prerrequisitos.sh
```
