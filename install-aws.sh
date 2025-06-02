# install-aws.sh
#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

echo "➤ Reparando /etc/apt/sources.list…"
sudo tee /etc/apt/sources.list >/dev/null <<'EOF'
deb http://archive.ubuntu.com/ubuntu focal main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu focal-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu focal-security main restricted universe multiverse
EOF

echo "➤ Limpiando caché de APT…"
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get clean

echo "➤ Actualizando índices de paquetes…"
sudo apt-get update -y

echo "➤ Instalando dependencias base…"
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

echo "➤ Instalando Nginx…"
sudo apt-get install -y nginx

echo "➤ Instalando Node.js ${NODE_VERSION}…"
curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}" | sudo -E bash -
sudo apt-get install -y nodejs build-essential

echo "➤ Creando aplicación demo…"
sudo mkdir -p /opt/nodeapp
sudo tee /opt/nodeapp/server.js >/dev/null <<'EOF'
const http = require('http');
http.createServer((_, res) => res.end('Hello from Node + Nginx!'))
     .listen(3000, () => console.log('Node escuchando en 3000'));
EOF

echo "➤ Configurando servicio systemd…"
sudo tee /etc/systemd/system/nodeapp.service >/dev/null <<'EOF'
[Unit]
Description=Node Demo
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/nodeapp/server.js
Restart=always
User=www-data
Environment=NODE_ENV=production
WorkingDirectory=/opt/nodeapp

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now nodeapp

echo "➤ Configurando Nginx como proxy inverso…"
sudo tee /etc/nginx/sites-available/nodeapp >/dev/null <<'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/nodeapp /etc/nginx/sites-enabled/nodeapp
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

echo "✅ Provisionamiento completo."
