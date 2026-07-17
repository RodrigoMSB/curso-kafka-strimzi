# Lab 04 — La puerta segura

Las aplicaciones del banco viven **fuera** del clúster Kubernetes. En este lab se
abre la puerta al exterior — sin abrir un hoyo — con dos listeners externos
autenticados (SCRAM para aplicaciones, mTLS para servicios críticos), se conecta
desde la terminal con `kcat`, y se cierra para siempre la puerta vieja (el
listener plano).

## Objetivos del lab

- Entender los tipos de listener y por qué kind usa `nodeport` (y EKS, `loadbalancer`).
- Exponer el clúster con dos listeners externos: TLS+SCRAM y mTLS.
- Producir y consumir **desde la terminal del host** con `kcat`.
- Leer el manifiesto de referencia de EKS (NLB) y entender qué cambia en producción.
- Eliminar el listener plano y distinguir "conexión rechazada" de "autorización denegada".

## Prerrequisitos

- **Lab 03 completado**. Si no, recupéralo con `labs/lab-03-topicos-identidad/bin/95-recuperar-lab.sh`.
- **kcat instalado**: `brew install kcat` (macOS) o `sudo apt-get install -y kcat` (Debian/Ubuntu/WSL2).
- El clúster con los **mapeos de puerto** del curso (32000–32007). Si tu clúster es anterior, recréalo (el verificador te lo indica).
- Verifica todo con: `bash bin/00-verificar-prerrequisitos.sh`.

## Tiempo estimado

Un bloque de 40 minutos (guías 1–5).

## Mapa del lab

| Guía | Archivo | Qué logras |
|------|---------|------------|
| 1 | `guia/01-mapa-de-puertas.md` | Entiendes los tipos de listener y la decisión nodeport vs loadbalancer. |
| 2 | `guia/02-abrir-la-puerta.md` | Añades los dos listeners externos y observas el rolling y el status. |
| 3 | `guia/03-kcat-desde-fuera.md` | Produces el primer mensaje desde fuera con kcat (SCRAM). |
| 4 | `guia/04-mtls-y-referencia-eks.md` | Consumes por mTLS y lees la referencia de EKS (NLB). |
| 5 | `guia/05-cerrar-la-puerta-vieja.md` | Eliminas el listener plano y distingues conexión vs autorización. |
| 6 | `guia/06-la-puerta-http.md` | **Anexo:** despliegas el Kafka Bridge y le das entrada al cliente que solo habla HTTP, sin abrir un agujero. |

## Verifica tu trabajo

```bash
bash bin/90-test-lab.sh
```

(El check insignia produce y consume con `kcat` **desde tu host**; necesita kcat
instalado.)

## Seguridad de las credenciales

El directorio `credenciales/` contiene material sensible local (la CA del
clúster, la contraseña SCRAM y el certificado/llave de cliente). **Nunca se
versiona** (está en el `.gitignore`) y **se elimina al destruir el clúster** con
`bin/99-destruir-lab.sh` (los certificados mueren con el clúster que los emitió).
Si compartes tu carpeta de trabajo por otro medio (un zip, etc.), elimínalo
antes.

## Para el instructor

- `bin/91-test-e2e.sh` certifica el lab completo de cero (Lab 01 → 04), con kcat desde el host, y limpia. No corras dos e2e a la vez: ambos mapean los puertos 32000–32007 del host.
- `bin/95-recuperar-lab.sh` reconstruye el estado final del Lab 04 para un alumno rezagado.
