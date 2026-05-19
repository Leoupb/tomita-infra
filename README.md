# Tomita API — Infraestructura AWS
**Curso:** Diseño y Gestión de Infraestructura Tecnológica — UPB  
**Docente:** Omar Pinzón Ardila

---

## Arquitectura

```
Internet
   │
   ▼
[ALB — Application Load Balancer]  (SG-ALB: puerto 80 abierto)
   │                │
   ▼                ▼
[EC2-1 us-east-1a] [EC2-2 us-east-1b]  (SG-EC2: solo desde ALB:3000)
Subnet pública     Subnet pública
   │                │
   └──────┬─────────┘
          ▼
[RDS MySQL Primary]  [RDS Read Replica]  (SG-RDS: solo desde EC2:3306)
Subnet privada 1a    Subnet privada 1b
```

**VPC:** `10.0.0.0/16`  
| Subnet | CIDR | AZ | Propósito |
|---|---|---|---|
| public-1a | 10.0.1.0/24 | us-east-1a | ALB + EC2 |
| public-1b | 10.0.2.0/24 | us-east-1b | ALB + EC2 |
| private-1a | 10.0.3.0/24 | us-east-1a | RDS Primary |
| private-1b | 10.0.4.0/24 | us-east-1b | RDS Replica |

---

## Pre-requisitos (hacer UNA sola vez)

### 1. Instalar herramientas
```bash
# Terraform
winget install HashiCorp.Terraform

# AWS CLI
winget install Amazon.AWSCLI

# k6
winget install k6 --source winget

# Verificar
terraform -v && aws --version && k6 version
```

### 2. Crear Key Pair en AWS Academy
1. Consola AWS → EC2 → Key Pairs → **Create key pair**
2. Nombre: `tomita-key`, formato: `.pem`
3. Guardar el archivo `.pem` descargado

### 3. Configurar credenciales de AWS Academy
```bash
aws configure
# Access Key ID:     (copiar de AWS Details en Learner Lab)
# Secret Access Key: (copiar de AWS Details)
# Region:            us-east-1
# Output format:     json

# Session Token (OBLIGATORIO en Academy):
$env:AWS_SESSION_TOKEN="pegar_session_token_aqui"   # PowerShell
```

---

## Despliegue con Terraform

```bash
cd terraform

# Copiar y completar variables
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars con tu key_name y db_password

# Paso 1 — Inicializar
terraform init

# Paso 2 — Revisar qué se creará
terraform plan

# Paso 3 — Desplegar (~10-15 min por RDS)
terraform apply

# Paso 4 — Ver outputs
terraform output
```

**Outputs esperados:**
```
alb_dns_name        = "tomita-alb-XXXXXXXX.us-east-1.elb.amazonaws.com"
service_url         = "http://tomita-alb-XXXXXXXX.us-east-1.elb.amazonaws.com"
health_check_url    = "http://tomita-alb-XXXXXXXX.us-east-1.elb.amazonaws.com/health"
asg_name            = "tomita-asg"
```

---

## Validar el servicio desplegado

```bash
# Reemplazar ALB_DNS con el valor del output
export ALB="http://tomita-alb-XXXXXXXX.us-east-1.elb.amazonaws.com"

curl $ALB/health
curl $ALB/status
curl $ALB/api/test
curl $ALB/api/productos

# Crear un producto
curl -X POST $ALB/api/productos \
  -H "Content-Type: application/json" \
  -d '{"nombre": "Pintura Turquesa", "precio": 3000}'
```

---

## GitHub Actions — CI/CD

### Configurar Secrets en GitHub
Ir a: **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | Copiar de AWS Academy Details |
| `AWS_SECRET_ACCESS_KEY` | Copiar de AWS Academy Details |
| `AWS_SESSION_TOKEN` | Copiar de AWS Academy Details |
| `DB_PASSWORD` | Contraseña definida en tfvars |

### Flujo del pipeline
1. **Push a cualquier rama** → Job `test`: lint + pruebas unitarias
2. **Pull Request** → Job `terraform-plan`: muestra qué cambiaría
3. **Push a main** → Job `deploy`: `terraform apply` + actualiza app en EC2 via SSM

---

## Prueba de desempeño con k6

```bash
# Instalar k6 si no está
winget install k6 --source winget

# Ejecutar prueba de carga
k6 run -e BASE_URL=http://ALB-DNS-AQUI k6/load-test.js
```

### Etapas de la prueba
| Etapa | Duración | VUs | Propósito |
|---|---|---|---|
| Calentamiento | 30s | 0→10 | Baseline |
| Carga normal | 1m | 10→30 | Operación típica |
| Carga alta | 1m | 30→60 | Forzar balanceo ALB |
| Pico saturación | 30s | 60→100 | Límite del sistema |
| Enfriamiento | 30s | 100→0 | Recuperación |

### Evidencia del balanceador
En el output final verás algo como:
```
Distribución por instancia (ALB):
  ip-10-0-1-XXX: 1823 requests
  ip-10-0-2-YYY: 1811 requests    ← distribución ~50/50
```

### Verificar en CloudWatch
1. Consola AWS → **CloudWatch** → Metrics
2. **AWS/ApplicationELB** → `RequestCount` por `TargetGroup`
3. Observar que ambas instancias reciben tráfico
4. **AWS/EC2** → `CPUUtilization` filtrado por `AutoScalingGroupName`

---

## Destruir la infraestructura (después del video)
```bash
cd terraform
terraform destroy
```

---

## Justificaciones de diseño

| Decisión | Justificación |
|---|---|
| **ALB + ASG min 2** | Alta disponibilidad: si una instancia falla, el ALB redirige al nodo sano. El ASG reemplaza instancias automáticamente. |
| **EC2 en subnets públicas** | AWS Academy limita NAT Gateway; los EC2 necesitan acceso a Internet para instalación. El SG-EC2 restringe tráfico de aplicación a solo el ALB. |
| **RDS en subnets privadas** | La DB nunca tiene IP pública; SG-RDS solo permite conexiones desde EC2 en el mismo VPC, eliminando exposición directa. |
| **Read Replica en AZ distinta** | Distribuye lecturas y sirve como failover en caso de fallo de la AZ primaria. |
| **Target Tracking 70% CPU** | Escalado automático proactivo antes de saturación; 70% deja margen para absorber picos sin degradación. |
