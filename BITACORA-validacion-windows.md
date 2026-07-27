# Bitácora de validación — Windows / VM Netec
### Curso Kafka-Strimzi · Banco Meridiano · Actualizada 25-jul-2026

> Lo que descubrimos validando en la máquina real. **Ten esto abierto en clase.**
> No es teoría del curso: son las cosas que muerden en Windows y entre sesiones.

---

## 🔴 LAS CUATRO QUE TE VAN A PASAR EN SALA

### 1 · Ctrl+C mata el proceso (no copia)

En Git Bash, `Ctrl+C` envía **SIGINT**. Es el reflejo de Windows y ya nos costó una
corrida de 24 minutos.

- **Para copiar:** selecciona con el mouse (copia sola) o usa clic derecho.
- **Para procesos largos:** manda la salida a un archivo y léela desde **otra** terminal.
  ```bash
  bash <script> 2>&1 | tee /c/STRIMZI/salida.log
  # en otra Git Bash:
  tail -f /c/STRIMZI/salida.log
  ```
- **Dilo el lunes, antes del primer script largo.** A los 15 les va a pasar.

### 2 · Docker Desktop se roba el contexto de kubectl

Al reiniciar la máquina, Docker Desktop se pone a sí mismo como contexto por defecto.
Resultado: `kubectl get nodes` muestra **un solo nodo** (`desktop-control-plane`) y todos
los comandos "no encuentran nada".

```bash
kubectl config current-context          # ¿dice docker-desktop?
kubectl config use-context kind-meridiano
```

**Recomendación para la imagen:** desactivar Kubernetes en Docker Desktop
(*Settings → Kubernetes → Enable Kubernetes*, desmarcar). kind usa el **engine** de Docker,
no su Kubernetes. Quitarlo elimina la confusión y libera memoria. → **Pedírselo a Jesús.**

### 3 · `cliente-kafka` no sobrevive a un reinicio

Es un **pod suelto, sin controlador**. Cuando la máquina se reinicia queda en `Unknown` y
**nadie lo repone**. A partir de ahí, todo `kubectl exec cliente-kafka` falla sin un error
claro, y las guías 04 y 05 del Lab 03 dejan de funcionar.

```bash
kubectl delete pod cliente-kafka -n meridiano-pagos --force --grace-period=0
bash labs/lab-03-topicos-identidad/bin/01-preparar-cliente.sh
```

> **El miércoles, cuando vuelvan de la sesión del martes, le va a pasar a los 15.**
> Ténlo en la punta de la lengua.

**Y aprovéchalo como lección:** los brokers y el entity-operator **se repusieron solos**
(tienen StrimziPodSet detrás); el pod suelto no. *Lo declarado se reconcilia; lo suelto, no.*

### 4 · El consumidor muestra 0 mensajes y la guía dice que verás uno

**Guía 04 del Lab 03.** Si antes corriste el `90-test` o el `95`, el grupo
`fraude.deteccion` **ya dejó su offset al final**. Y `--from-beginning`
**solo aplica si el grupo NO tiene offset comprometido**.

- **Salida rápida:** produce un mensaje fresco justo antes de demostrarlo.
- **Alternativa:** usa otro nombre de grupo en la demo.
- **Mejor:** conviértelo en lección. *«¿Por qué no veo nada si dije from-beginning?»*
  → porque la cuadrilla ya dejó su **marcapáginas**, y respeta el marcapáginas antes que
  la instrucción. Es el concepto de offset, ocurriendo en vivo.

---

## 🟢 RESUELTO — SPEC-011 (rama `fix/spec-011-portabilidad-windows`)

**El bug:** Git Bash (MSYS2) reescribía `/props/...` a `C:/Program Files/Git/props/...`,
rompiendo todo consumidor que pasara la ruta como argumento directo.

**Certificado en Windows, VM de Netec:**

| Momento | Resultado |
|---|---|
| Antes del fix (misma máquina, misma sesión) | **6/7** — round-trip rojo |
| Después del `checkout` de la rama | **7/7** ✅ |
| Comandos de la guía 04 tecleados a mano | `TX-9999` recibido ✅ |
| Verificador de entorno | `[INFO]` de Git Bash aparece ✅ |

**Nota (corregida por SPEC-012/013/014):** esto era falso. Los `lib-comunes.sh` **ya no**
exportan `MSYS_NO_PATHCONV`, y el `export` manual **nunca** hizo falta: rompía `kind`, `helm`
y `kubectl`. El bug de rutas de MSYS2 se resuelve de dos formas, ambas de alcance acotado:
envolviendo el comando en `bash -c '...'` (guías y `kubectl exec`) o prefijando la variable
**en línea** en los `docker run/exec` cuyas rutas son todas del contenedor.

---

## 🟡 PENDIENTES / A VIGILAR

| # | Tema | Estado |
|---|---|---|
| 1 | **kubectl v1.36.1 vs nodos v1.34.8** — 2 minors de skew, fuera de ±1. El lab está probado así y el verificador lo marca `[INFO]`. | Aceptado. Pedirle a Jesús un kubectl ~1.34/1.35 en la imagen si se puede. |
| 2 | **4 CPUs** en la VM. Tu spec fija RAM pero no CPU. Vigilar el build de Debezium (Lab 05) y el rebalanceo (Lab 07). | Sin evidencia de que falte. No pedir cambio sin datos: **recrea la VM y pierdes todo**. |
| 3 | **El pico de memoria del e2e (~4,6 GiB) NO es válido.** La corrida falló en Fase 1 y nunca desplegó DR, observabilidad ni Connect. | Repetir el `91` completo cuando el fix esté en main, para tener el número real. |
| 4 | **La sesión RDP se cae.** El clúster sobrevive (disco persistente), pero los procesos en curso mueren. | Siempre `tee` en lo largo. |

---

## 📕 ERRORES EN TU MATERIAL DE INSTRUCTOR (corregir antes de usarlo)

| # | Dónde | Qué está mal |
|---|---|---|
| 1 | Diagrama **«El tópico fantasma»** | Dice que el operador **borra** un tópico no declarado. **Falso**: el Topic Operator unidireccional solo gestiona lo declarado; lo demás **convive intacto** — y tu propio Lab 03 lo demuestra con `tmp.pruebas.libre`. Lo que sí revierte es el **drift de configuración** de un tópico ya declarado. |
| 2 | Diagrama **«El edificio con varias puertas»** | Puertos equivocados. Dice *externa 9094 SCRAM* y *externa 9095 mTLS*. **La realidad:** 9093 tls y 9094 scram son **internos**; los externos son **9095 (extscram)** y **9096 (extmtls)**, que salen al host por 32000-32003 y 32004-32007. También dice que 9092 era "tráfico entre brokers": era el listener **de clientes**. |
| 3 | GUIA-TEORICA, sección CRDs | Dice *«10 palabras nacieron»* y **lista nueve**. Strimzi 0.51 instala **9 CRDs**. |

---

## ✅ ESTADO DEL AMBIENTE (VM Netec)

- RAM **32.763 MB** · Docker **20,52 GiB** · **4 CPUs** → conforme a spec
- kind **v0.32.0** en `~/bin`, con el PATH ya en `.bashrc` (permanente)
- Clúster **`meridiano`**: 4 nodos `Ready`, k8s **v1.34.8**
- Repo en `/c/STRIMZI/curso-kafka-strimzi`
- Estado actual: **Lab 03 desplegado y endurecido**, 7/7

### Antes de que Jesús saque la imagen
- [ ] Mergear SPEC-011 a `main` y dejar la VM en `main` (no en la rama)
- [ ] Desactivar Kubernetes en Docker Desktop (hallazgo #2)
- [ ] ⚠️ **NUNCA** dejar `MSYS_NO_PATHCONV` en el `.bashrc` de la imagen (ni exportarla en
      ninguna terminal). Apaga la conversión de rutas de forma global y rompe `kind`, `helm`
      y `kubectl`, que **sí la necesitan** para leer archivos del disco de Windows: el primer
      comando del curso (`01-crear-cluster.sh`) falla con `The system cannot find the path
      specified`. **Verificar que la imagen no la traiga** de pruebas anteriores:
      `grep -rn MSYS_NO_PATHCONV ~/.bashrc ~/.bash_profile ~/.profile` debe salir vacío.
      El verificador del Lab 01 ya la detecta y falla con `[ERROR]` si está puesta.
- [ ] Decidir en qué estado se entrega el clúster a los alumnos (¿Lab 01 listo? ¿vacío?)

---

## Comandos de rescate (los que más vas a usar)

```bash
# ¿a qué clúster le estoy hablando?
kubectl config current-context && kubectl config use-context kind-meridiano

# el pod cliente murió
bash labs/lab-03-topicos-identidad/bin/01-preparar-cliente.sh

# recuperar el estado de un lab (tu paracaídas)
bash labs/lab-0N-.../bin/95-recuperar-lab.sh

# verificar dónde estoy parado
bash labs/lab-0N-.../bin/90-test-lab.sh

# las tres preguntas que ordenan cualquier situación
kubectl get kafka,kafkanodepool -n meridiano-pagos      # ¿qué dice el contrato?
kubectl get pods,pvc -n meridiano-pagos                 # ¿qué hay de verdad?
kubectl logs -n meridiano-sistema deploy/strimzi-cluster-operator --tail=30
```
