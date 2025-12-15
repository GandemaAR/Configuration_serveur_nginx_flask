#!/bin/bash

# Script d'automatisation d'installation Flask avec Nginx et Gunicorn
# À exécuter avec sudo

set -e  # Arrêter le script en cas d'erreur

echo "=== Début de l'installation ==="

# 1) Installation des paquets requis
echo "=== Installation des paquets ==="
apt update
apt install -y openssh-sftp-server nginx python3 python3-venv python3-pip gunicorn

# 2) Création du fichier de configuration Nginx
echo "=== Configuration de Nginx ==="

# Vérifier si le répertoire /etc/nginx/sites-available existe
if [ ! -d "/etc/nginx/sites-available" ]; then
    mkdir -p /etc/nginx/sites-available
fi

# Vérifier si le répertoire /etc/nginx/sites-enabled existe
if [ ! -d "/etc/nginx/sites-enabled" ]; then
    mkdir -p /etc/nginx/sites-enabled
fi

# Créer le fichier de configuration Nginx
cat > /etc/nginx/sites-available/bangre << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name bangre.com www.bangre.local;
    
    location /uploads/ {
        alias /home/dietpi/bangre/uploads/;
    }
    
    location ~ \.php$ {
        deny all;
    }
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
    
    access_log /var/log/nginx/app_bangre_access.log;
    error_log /var/log/nginx/app_bangre_error.log;
}
EOF

echo "Fichier de configuration Nginx créé"

# 3) Supprimer le site par défaut si il existe
echo "=== Suppression du site par défaut ==="
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    rm /etc/nginx/sites-enabled/default
    echo "Site par défaut supprimé"
else
    echo "Site par défaut non trouvé, continuation..."
fi

# 4) Activer le site bangre
echo "=== Activation du site bangre ==="
ln -sf /etc/nginx/sites-available/bangre /etc/nginx/sites-enabled/

# 5) Création du service systemd
echo "=== Création du service systemd ==="

# Créer le répertoire pour les logs si nécessaire
mkdir -p /home/dietpi/logs

cat > /etc/systemd/system/app_bangre.service << 'EOF'
[Unit]
Description=Application Gestion Fichiers Flask
After=network.target

[Service]
Type=simple
User=dietpi
Group=dietpi
WorkingDirectory=/home/dietpi/bangre
Environment="PATH=/home/dietpi/bangre/venv/bin"
ExecStart=/home/dietpi/bangre/venv/bin/gunicorn --bind 127.0.0.1:5000 --workers 2 --access-logfile /home/dietpi/logs/gunicorn_access.log --error-logfile /home/dietpi/logs/gunicorn_error.log --log-level info app:app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6) Configuration de l'environnement Python
echo "=== Configuration de l'environnement Python ==="

# Se déplacer dans le répertoire de l'application
cd /home/dietpi/bangre

# 7) Créer l'environnement virtuel
echo "=== Création de l'environnement virtuel ==="
python3 -m venv venv

# Activer l'environnement virtuel
source venv/bin/activate

# 8) Installer les dépendances Python
echo "=== Installation des dépendances Python ==="

# Vérifier si requirements.txt existe
if [ -f "requirements.txt" ]; then
    pip install --upgrade pip
    pip install -r requirements.txt
else
    echo "Fichier requirements.txt non trouvé, installation des dépendances de base..."
    pip install --upgrade pip
    pip install flask gunicorn
    # Créer un fichier requirements.txt de base
    pip freeze > requirements.txt
fi

# 9) Recharger les services
echo "=== Rechargement des services ==="

# Tester la configuration Nginx
nginx -t

# Recharger Nginx
systemctl reload nginx

# Recharger les daemons systemd
systemctl daemon-reload

# Activer et démarrer le service
systemctl enable app_bangre.service
systemctl start app_bangre.service

echo "=== Installation terminée avec succès! ==="
echo ""
echo "Vérifications à faire:"
echo "1. Vérifier que l'application est en cours d'exécution: sudo systemctl status app_bangre.service"
echo "2. Vérifier que Nginx fonctionne: sudo systemctl status nginx"
echo "3. Vérifier les logs en cas de problème:"
echo "   - Logs Nginx: /var/log/nginx/app_bangre_error.log"
echo "   - Logs Gunicorn: /home/dietpi/logs/gunicorn_error.log"
echo ""
echo "Pour tester l'application, visitez: http://bangre.local"
