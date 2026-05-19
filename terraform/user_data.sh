#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Variables inyectadas por Terraform templatefile
# ─────────────────────────────────────────────
DB_HOST="${db_host}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_NAME="${db_name}"
REGION="${region}"

# ─────────────────────────────────────────────
# 1. Actualizar sistema e instalar dependencias
# ─────────────────────────────────────────────
yum update -y
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs git

# Instalar PM2 globalmente para gestión de procesos
npm install -g pm2

# ─────────────────────────────────────────────
# 2. Clonar el repositorio de la aplicación
# ─────────────────────────────────────────────
mkdir -p /opt/tomita-api
cd /opt/tomita-api

# Clonar desde GitHub (repositorio público)
git clone https://github.com/TU_USUARIO/tomita-infra.git . 2>/dev/null || \
  git pull origin main 2>/dev/null || true

cd /opt/tomita-api/app
npm install --production

# ─────────────────────────────────────────────
# 3. Configurar variables de entorno
# ─────────────────────────────────────────────
cat > /opt/tomita-api/app/.env <<EOF
NODE_ENV=production
PORT=3000
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_NAME=$DB_NAME
AWS_REGION=$REGION
EOF

# Obtener ID de la instancia desde metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "unknown")
echo "INSTANCE_ID=$INSTANCE_ID" >> /opt/tomita-api/app/.env

# ─────────────────────────────────────────────
# 4. Inicializar base de datos (primera vez)
# ─────────────────────────────────────────────
sleep 30  # Esperar a que RDS esté disponible

# Script de inicialización DB
node - <<'INITDB'
const mysql = require('mysql2/promise');
const fs = require('fs');
require('dotenv').config({ path: '/opt/tomita-api/app/.env' });

async function init() {
  try {
    const conn = await mysql.createConnection({
      host: process.env.DB_HOST,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
    });
    await conn.query(`CREATE DATABASE IF NOT EXISTS ${process.env.DB_NAME}`);
    await conn.query(`USE ${process.env.DB_NAME}`);
    await conn.query(`
      CREATE TABLE IF NOT EXISTS productos (
        id      INT AUTO_INCREMENT PRIMARY KEY,
        nombre  VARCHAR(100) NOT NULL,
        precio  DECIMAL(10,2) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    await conn.query(`
      INSERT IGNORE INTO productos (id, nombre, precio) VALUES
        (1, 'Pintura Blanco Hueso',  2500),
        (2, 'Pintura Azul Celeste',  3200),
        (3, 'Pintura Blanco Mate',   2800),
        (4, 'Pintura Verde',         3120),
        (5, 'Pintura Lila',          2800)
    `);
    console.log('Base de datos inicializada correctamente');
    await conn.end();
  } catch (err) {
    console.error('DB init error (no critico):', err.message);
  }
}
init();
INITDB

# ─────────────────────────────────────────────
# 5. Iniciar aplicación con PM2
# ─────────────────────────────────────────────
cd /opt/tomita-api/app
pm2 start src/app.js --name "tomita-api" --env production
pm2 startup systemd -u ec2-user --hp /home/ec2-user
pm2 save

# ─────────────────────────────────────────────
# 6. Instalar CloudWatch Agent
# ─────────────────────────────────────────────
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<CWCONF
{
  "agent": { "metrics_collection_interval": 60 },
  "metrics": {
    "append_dimensions": {
      "AutoScalingGroupName": "\${aws:AutoScalingGroupName}",
      "InstanceId": "\${aws:InstanceId}"
    },
    "metrics_collected": {
      "cpu":    { "measurement": ["cpu_usage_active"], "metrics_collection_interval": 60 },
      "mem":    { "measurement": ["mem_used_percent"],  "metrics_collection_interval": 60 },
      "disk":   { "measurement": ["disk_used_percent"], "resources": ["/"], "metrics_collection_interval": 60 }
    }
  }
}
CWCONF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "Bootstrap completado - Tomita API iniciada"
