# Guía 1 — El mapa de puertas

Las aplicaciones del banco no viven dentro de Kubernetes: corren en otros
servidores, en otra red. Hasta ahora, todo lo que hicimos fue **dentro** del
clúster (pods cliente). Hoy abrimos una puerta hacia fuera — sin abrir un hoyo.

## Prerrequisitos

```bash
bash bin/00-verificar-prerrequisitos.sh
```

Verifica tres cosas: el estado del Lab 03, que **kcat** esté instalado, y que tu
clúster tenga mapeados los puertos externos del curso (32000–32007). Si faltan
esos mapeos, tu clúster es anterior al contrato de puertos: recréalo siguiendo
las instrucciones que imprime el script.

> **kcat** es un cliente de Kafka de línea de comandos, liviano, que correremos
> desde **tu terminal** (fuera del clúster). Instálalo con `brew install kcat`
> (macOS) o `sudo apt-get install -y kcat` (Debian/Ubuntu/WSL2).
> En **Windows**, el verificador de prerrequisitos configura kcat automáticamente
> (lo usa desde Ubuntu/WSL2, porque no existe binario nativo para Windows).

## Los tipos de listener

Un *listener* es una puerta del clúster. Strimzi ofrece cuatro tipos:

| Tipo | Dónde se alcanza | Cuándo se usa |
|------|------------------|----------------|
| `internal` | Solo dentro del clúster | Clientes que corren como pods (labs 02–03). |
| `nodeport` | Por un puerto de cada nodo | Acceso externo simple; **lo único que kind soporta**. |
| `loadbalancer` | Por un balanceador del proveedor | Producción en la nube (EKS → NLB). |
| `route` | Por rutas de OpenShift | Clústeres OpenShift. |

### La decisión

- **En producción sobre EKS**, un banco usaría `loadbalancer`: Strimzi provisiona
  un **AWS Network Load Balancer (NLB)** y los clientes se conectan por su DNS.
- **En este laboratorio** no hay balanceadores: kind no los provisiona. Por eso
  usamos `nodeport` y un puente de puertos hacia tu host. El manifiesto de
  referencia para EKS (`loadbalancer` + NLB) lo estudiarás en la guía 4.

## Una regla clave: un mecanismo de autenticación por listener

Cada listener admite **un solo** mecanismo de autenticación. No puedes mezclar
SCRAM y mTLS en la misma puerta. Por eso, para exponer el clúster a clientes
externos, Meridiano abre **dos** puertas:

- una **SCRAM** (TLS + usuario/contraseña) para las **aplicaciones**;
- una **mTLS** (certificado de cliente) para los **servicios críticos**.

Es el patrón real de un banco: las apps de negocio se autentican con
credenciales; los servicios sensibles, con certificados. En la siguiente guía
abrimos ambas.
