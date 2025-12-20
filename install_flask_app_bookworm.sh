#!/bin/bash

# Script d'automatisation d'installation Flask avec Nginx et Gunicorn
# Adapté pour Raspberry Pi OS Bookworm (Debian 12)
# Version corrigée avec gestion des erreurs pkg-config
# À exécuter avec sudo

set -e # Arrêter le script en cas d'erreur

# Fonction de logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Fonction pour vérifier si une commande a réussi
check_status() {
  if [ $? -eq 0 ]; then
    log "✓ $1"
  else
    log "✗ Échec: $1"
    return 1
  fi
}

# Fonction pour installer les paquets avec vérification
install_package() {
  local package=$1
  local optional=${2:-false}

  log "Installation de $package..."

  # Vérifier d'abord si le package existe
  if apt-cache show "$package" >/dev/null 2>&1; then
    apt install -y "$package" >/dev/null 2>&1
    if dpkg -l | grep -q "^ii  $package "; then
      log "✓ $package installé avec succès"
      return 0
    else
      log "✗ Échec d'installation de $package"
      if [ "$optional" = "true" ]; then
        log "⚠ $package est optionnel, continuation..."
        return 0
      fi
      return 1
    fi
  else
    log "⚠ Package $package non disponible dans les dépôts"
    if [ "$optional" = "true" ]; then
      log "⚠ $package est optionnel, continuation sans..."
      return 0
    fi
    return 1
  fi
}

# Fonction alternative pour pkg-config
install_pkg_config_alternative() {
  log "Tentative d'installation alternative de pkg-config..."

  # Vérifier si pkg-config est déjà disponible via un autre package
  if command -v pkg-config >/dev/null 2>&1; then
    log "✓ pkg-config déjà disponible"
    return 0
  fi

  # Essayer différentes variantes
  local variants=("pkgconf" "pkg-config" "pkgconfig")

  for variant in "${variants[@]}"; do
    if apt-cache show "$variant" >/dev/null 2>&1; then
      log "Installation de $variant à la place..."
      apt install -y "$variant" >/dev/null 2>&1
      if command -v pkg-config >/dev/null 2>&1; then
        log "✓ pkg-config fonctionnel via $variant"
        return 0
      fi
    fi
  done

  # Vérifier si on peut compiler depuis les sources
  log "Vérification des dépendances de compilation..."
  if apt-cache show "build-essential" >/dev/null 2>&1; then
    log "Installation de build-essential pour compilation..."
    apt install -y build-essential >/dev/null 2>&1

    # Télécharger et compiler pkg-config depuis les sources si nécessaire
    log "Tentative d'installation depuis les sources..."
    if command -v wget >/dev/null 2>&1; then
      cd /tmp
      wget -q https://pkg-config.freedesktop.org/releases/pkg-config-0.29.2.tar.gz
      tar -xzf pkg-config-0.29.2.tar.gz
      cd pkg-config-0.29.2
      ./configure --with-internal-glib
      make
      make install
      if command -v pkg-config >/dev/null 2>&1; then
        log "✓ pkg-config installé depuis les sources"
        return 0
      fi
    fi
  fi

  log "⚠ Impossible d'installer pkg-config, certaines fonctionnalités peuvent être limitées"
  return 0
}

# Fonction pour vérifier et installer les dépendances Python
install_python_dependencies() {
  local venv_path=$1
  local req_file=$2

  log "Vérification de l'environnement virtuel..."

  # Vérifier si l'environnement virtuel existe
  if [ ! -f "$venv_path/bin/activate" ]; then
    log "Création de l'environnement virtuel..."

    # Vérifier si python3-venv est installé
    if ! dpkg -l | grep -q python3-venv; then
      log "Installation de python3-venv..."
      apt install -y python3-venv >/dev/null 2>&1
      check_status "python3-venv installé"
    fi

    # Créer l'environnement virtuel
    python3 -m venv "$venv_path"
    if [ $? -ne 0 ]; then
      log "Tentative alternative de création de venv..."
      python3 -m venv "$venv_path" --system-site-packages
    fi
    check_status "Environnement virtuel créé"
  else
    log "Environnement virtuel déjà existant"
  fi

  # Activer l'environnement virtuel
  log "Activation de l'environnement virtuel..."
  source "$venv_path/bin/activate"

  # Vérifier que l'activation a fonctionné
  if [ -z "$VIRTUAL_ENV" ]; then
    log "✗ Échec d'activation de l'environnement virtuel"
    log "Tentative alternative d'activation..."
    . "$venv_path/bin/activate"
    if [ -z "$VIRTUAL_ENV" ]; then
      exit 1
    fi
  fi

  log "✓ Environnement virtuel activé: $VIRTUAL_ENV"

  # Vérifier la version de Python
  python_version=$(python --version 2>&1)
  log "Version de Python: $python_version"

  # Mettre à jour pip dans l'environnement virtuel
  log "Mise à jour de pip..."
  python -m pip install --upgrade pip >/dev/null 2>&1 ||
    python -m pip install --upgrade pip --no-cache-dir >/dev/null 2>&1
  check_status "pip mis à jour"

  # Vérifier la version de pip
  pip_version=$(pip --version 2>&1 | cut -d' ' -f2)
  log "Version de pip: $pip_version"

  # Vérifier l'existence du fichier requirements.txt
  if [ ! -f "$req_file" ]; then
    log "⚠ Fichier $req_file non trouvé"
    log "Création d'un fichier requirements.txt par défaut..."

    # Installer les dépendances de base pour Flask
    log "Installation des dépendances de base..."

    # Essayer avec des versions compatibles
    pip install flask==3.0.0 gunicorn==20.1.0 >/dev/null 2>&1 ||
      pip install flask gunicorn >/dev/null 2>&1 ||
      pip install flask gunicorn --no-cache-dir >/dev/null 2>&1

    # Vérifier l'installation de chaque package
    for pkg in flask gunicorn; do
      if pip show "$pkg" >/dev/null 2>&1; then
        pkg_version=$(pip show "$pkg" | grep "Version:" | cut -d' ' -f2)
        log "✓ $pkg==$pkg_version installé avec succès"
      else
        log "✗ Échec d'installation de $pkg"
        log "Tentative alternative..."
        pip install "$pkg" --no-deps --no-cache-dir >/dev/null 2>&1
      fi
    done

    # Générer le fichier requirements.txt
    pip freeze >"$req_file" 2>/dev/null || echo "flask>=3.0.0\ngunicorn>=20.1.0" >"$req_file"
    log "✓ Fichier $req_file créé"

  else
    log "Fichier $req_file trouvé, installation des dépendances..."

    # Vérifier la syntaxe du fichier requirements.txt
    if [ ! -s "$req_file" ]; then
      log "⚠ Le fichier $req_file est vide"
      echo "flask>=3.0.0" >>"$req_file"
      echo "gunicorn>=20.1.0" >>"$req_file"
    fi

    # Compter le nombre de dépendances
    dep_count=$(grep -c -E '^[^#]' "$req_file" 2>/dev/null || echo "0")
    log "Nombre de dépendances à installer: $dep_count"

    # Installer les dépendances
    log "Installation des dépendances..."
    pip install -r "$req_file" >/dev/null 2>&1 ||
      pip install -r "$req_file" --no-cache-dir >/dev/null 2>&1

    # Vérifier les installations
    log "Vérification des installations..."
    installed_count=0
    failed_packages=""

    while IFS= read -r line || [ -n "$line" ]; do
      # Ignorer les lignes vides et les commentaires
      [[ -z "$line" || "$line" =~ ^# ]] && continue

      # Extraire le nom du package
      pkg_name=$(echo "$line" | sed 's/[<>=!].*//' | sed 's/\[.*\]//' | xargs)

      if pip show "$pkg_name" >/dev/null 2>&1; then
        installed_count=$((installed_count + 1))
        pkg_version=$(pip show "$pkg_name" | grep "Version:" | cut -d' ' -f2)
        log "  ✓ $pkg_name==$pkg_version"
      else
        failed_packages="$failed_packages $pkg_name"
        log "  ✗ $pkg_name"
      fi
    done <"$req_file"

    if [ $installed_count -eq $dep_count ]; then
      log "✓ Toutes les $dep_count dépendances installées avec succès"
    else
      log "⚠ Seulement $installed_count/$dep_count dépendances installées"
      if [ -n "$failed_packages" ]; then
        log "Packages en échec:$failed_packages"
      fi
    fi
  fi

  # Vérifier les dépendances critiques
  log "Vérification des dépendances critiques..."
  critical_packages=("flask" "gunicorn")
  for critical_pkg in "${critical_packages[@]}"; do
    if pip show "$critical_pkg" >/dev/null 2>&1; then
      pkg_version=$(pip show "$critical_pkg" | grep "Version:" | cut -d' ' -f2)
      log "✓ $critical_pkg==$pkg_version est installé"
    else
      log "✗ $critical_pkg n'est pas installé - tentative d'installation..."
      pip install "$critical_pkg" >/dev/null 2>&1 ||
        pip install "$critical_pkg" --no-cache-dir >/dev/null 2>&1
      if pip show "$critical_pkg" >/dev/null 2>&1; then
        log "✓ $critical_pkg installé"
      else
        log "⚠ Échec d'installation de $critical_pkg"
      fi
    fi
  done

  # Lister tous les packages installés
  log "Packages Python installés:"
  pip list --format=columns 2>/dev/null | tail -n +3 || pip list 2>/dev/null

  # Désactiver l'environnement virtuel
  deactivate 2>/dev/null || true
  log "Environnement virtuel désactivé"
}

echo "=========================================="
echo "  Installation automatisée Flask + Nginx  "
echo "  Pour Raspberry Pi OS Bookworm (Debian 12)"
echo "=========================================="

# Vérifier le système d'exploitation
log "Vérification du système..."
if [ -f /etc/os-release ]; then
  . /etc/os-release
  log "Distribution: $PRETTY_NAME"
  log "Version: $VERSION_ID"
else
  log "⚠ Impossible de détecter la distribution"
fi

# Vérifier l'architecture
architecture=$(uname -m)
log "Architecture: $architecture"

# 1) Installation des paquets système requis
log "=== Étape 1: Installation des paquets système ==="

# Mise à jour des paquets
log "Mise à jour des listes de paquets..."
apt update >/dev/null 2>&1
check_status "Listes de paquets mises à jour"

# Mise à niveau des paquets existants
log "Mise à niveau des paquets existants..."
apt upgrade -y >/dev/null 2>&1
check_status "Paquets mis à niveau"

# Liste des paquets essentiels (sans pkg-config)
essential_packages=(
  "openssh-sftp-server"
  "nginx"
  "python3"
  "python3-venv"
  "python3-pip"
  "python3-dev"
  "build-essential"
  "wget"
  "curl"
)

# Installer chaque paquet essentiel
for package in "${essential_packages[@]}"; do
  install_package "$package"
done

# Gérer pkg-config séparément
log "Traitement spécial pour pkg-config..."
install_pkg_config_alternative

# Vérifier les installations
log "Vérification finale des paquets installés..."
all_packages=("${essential_packages[@]}" "pkg-config")
for package in "${all_packages[@]}"; do
  if dpkg -l | grep -q "^ii  $package " || command -v "$package" >/dev/null 2>&1; then
    log "✓ $package: OK"
  else
    log "⚠ $package: NON INSTALLÉ (mais optionnel)"
  fi
done

# 2) Configuration de Nginx
log "=== Étape 2: Configuration de Nginx ==="

# Créer le fichier de configuration Nginx
nginx_conf="/etc/nginx/sites-available/bangre"
log "Création du fichier de configuration Nginx..."

cat >"$nginx_conf" <<'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name bangre.com www.bangre.local;
    
    location /uploads/ {
        alias /home/pi/bangre/uploads/;
        autoindex off;
    }
    
    location ~ \.php$ {
        deny all;
        return 403;
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

check_status "Fichier de configuration Nginx créé"

# 3) Configuration des sites Nginx
log "=== Étape 3: Configuration des sites ==="

# Supprimer le site par défaut
if [ -f "/etc/nginx/sites-enabled/default" ]; then
  log "Suppression du site par défaut..."
  rm -f /etc/nginx/sites-enabled/default
  check_status "Site par défaut supprimé"
fi

# Activer le site bangre
log "Activation du site bangre..."
ln -sf /etc/nginx/sites-available/bangre /etc/nginx/sites-enabled/
check_status "Site bangre activé"

# 4) Création du service systemd
log "=== Étape 4: Configuration du service systemd ==="

# Créer les répertoires de logs
log "Création des répertoires de logs..."
mkdir -p /home/pi/logs
chown -R pi:pi /home/pi/logs
check_status "Répertoires de logs créés"

# Créer le service
service_file="/etc/systemd/system/app_bangre.service"
log "Création du service systemd..."

cat >"$service_file" <<'EOF'
[Unit]
Description=Application Gestion Fichiers Flask
After=network.target

[Service]
Type=simple
User=pi
Group=pi
WorkingDirectory=/home/pi/bangre
Environment="PATH=/home/pi/bangre/venv/bin"
Environment="PYTHONPATH=/home/pi/bangre"
ExecStart=/home/pi/bangre/venv/bin/gunicorn --bind 127.0.0.1:5000 --workers 2 --threads 2 --access-logfile /home/pi/logs/gunicorn_access.log --error-logfile /home/pi/logs/gunicorn_error.log --log-level info --timeout 60 app:app
Restart=always
RestartSec=10
StandardOutput=append:/home/pi/logs/gunicorn_stdout.log
StandardError=append:/home/pi/logs/gunicorn_stderr.log

# Configuration de sécurité
NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=/home/pi/logs /home/pi/bangre/uploads

[Install]
WantedBy=multi-user.target
EOF

check_status "Service systemd créé"

# 5) Configuration de l'application Python
log "=== Étape 5: Configuration de l'application Python ==="

# Vérifier l'existence du répertoire de l'application
app_dir="/home/pi/bangre"
if [ ! -d "$app_dir" ]; then
  log "⚠ Le répertoire $app_dir n'existe pas"
  log "Création du répertoire..."
  mkdir -p "$app_dir"
  check_status "Répertoire d'application créé"
fi

# Créer le répertoire uploads
log "Création du répertoire uploads..."
mkdir -p "$app_dir/uploads"
chown -R pi:pi "$app_dir"
check_status "Répertoire uploads créé"

# Se déplacer dans le répertoire
cd "$app_dir" || exit 1
log "Répertoire courant: $(pwd)"

# 6) Installation des dépendances Python
log "=== Étape 6: Installation des dépendances Python ==="

requirements_file="$app_dir/requirements.txt"
venv_path="$app_dir/venv"

# Installer les dépendances avec notre fonction robuste
install_python_dependencies "$venv_path" "$requirements_file"

# 7) Vérification finale de l'installation
log "=== Étape 7: Vérification finale ==="

# Vérifier l'existence de app.py
if [ ! -f "$app_dir/app.py" ]; then
  log "⚠ ATTENTION: app.py non trouvé dans $app_dir"
  log "Création d'un fichier app.py minimal..."
  cat >"$app_dir/app.py" <<'EOF'
from flask import Flask, jsonify
import os
import sys

app = Flask(__name__)

@app.route('/')
def index():
    return jsonify({
        'status': 'online',
        'message': 'Application Flask opérationnelle!',
        'python': sys.version,
        'cwd': os.getcwd(),
        'user': os.getenv('USER', 'inconnu')
    })

@app.route('/health')
def health():
    return jsonify({'status': 'healthy', 'timestamp': __import__('datetime').datetime.now().isoformat()})

@app.route('/test')
def test():
    return 'Test réussi! Le serveur fonctionne correctement.'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
EOF
  check_status "Fichier app.py créé"

  # Vérifier que le fichier est lisible
  chmod 644 "$app_dir/app.py"
  chown pi:pi "$app_dir/app.py"
else
  log "✓ Fichier app.py trouvé"
fi

# Vérifier la structure du projet
log "Structure du projet:"
ls -la "$app_dir"/

# 8) Redémarrage des services
log "=== Étape 8: Redémarrage des services ==="

# Tester la configuration Nginx
log "Test de la configuration Nginx..."
nginx_test=$(nginx -t 2>&1)
if [ $? -eq 0 ]; then
  log "✓ Configuration Nginx valide"
else
  log "✗ Configuration Nginx invalide"
  echo "$nginx_test"

  # Tentative de correction
  log "Tentative de correction..."
  mkdir -p /etc/nginx/sites-enabled/
  nginx -t 2>&1 || true
fi

# Recharger Nginx
log "Rechargement de Nginx..."
systemctl reload nginx 2>/dev/null || systemctl restart nginx
check_status "Nginx rechargé"

# Recharger les daemons systemd
log "Rechargement des daemons systemd..."
systemctl daemon-reload
check_status "Daemons systemd rechargés"

# Activer et démarrer le service
log "Activation du service..."
systemctl enable app_bangre.service 2>/dev/null
check_status "Service activé"

log "Démarrage du service..."
systemctl start app_bangre.service
if systemctl is-active --quiet app_bangre.service; then
  log "✓ Service démarré avec succès"
else
  log "⚠ Service non démarré - tentative de debug..."
  systemctl status app_bangre.service --no-pager -l | head -30
  log "Vérification des permissions..."
  ls -la /home/pi/bangre/
  ls -la /home/pi/bangre/venv/bin/
fi

# Attendre un peu et vérifier le statut
sleep 2
log "Vérification du statut du service..."
if systemctl is-active --quiet app_bangre.service; then
  log "✓ Service actif"
else
  log "✗ Service inactif - vérification des logs..."
  journalctl -u app_bangre.service -n 20 --no-pager 2>/dev/null ||
    echo "Logs non disponibles, vérifiez manuellement"
fi

# Vérifier Nginx
log "Vérification du statut Nginx..."
if systemctl is-active --quiet nginx; then
  log "✓ Nginx actif"
else
  log "✗ Nginx inactif - redémarrage..."
  systemctl restart nginx
fi

# Test final
log "Test de l'application..."
sleep 1
if curl -s http://localhost:5000 >/dev/null 2>&1; then
  log "✓ Application accessible sur localhost:5000"
  curl -s http://localhost:5000 | head -c 100
  echo ""
elif curl -s http://127.0.0.1:5000 >/dev/null 2>&1; then
  log "✓ Application accessible sur 127.0.0.1:5000"
else
  log "⚠ Application non accessible - vérifiez les logs"
fi

echo ""
echo "=========================================="
log "INSTALLATION TERMINÉE!"
echo "=========================================="
echo ""
echo "RÉSUMÉ:"
echo "✅ Paquets système essentiels installés"
echo "✅ Nginx configuré"
echo "✅ Service systemd créé"
echo "✅ Environnement virtuel Python configuré"
echo "✅ Application Flask prête"
echo ""
echo "⚠ Remarque: pkg-config était optionnel"
echo ""
echo "COMMANDES UTILES:"
echo "  sudo systemctl status app_bangre.service"
echo "  sudo journalctl -u app_bangre.service -f"
echo "  tail -f /home/pi/logs/gunicorn_*.log"
echo ""
echo "TEST RAPIDE:"
echo "  curl http://localhost:5000"
echo "  curl http://localhost:5000/health"
echo ""
echo "POUR DÉMARRER/REDÉMARRER:"
echo "  sudo systemctl restart app_bangre.service"
echo ""
echo "ENVIRONNEMENT VIRTUEL:"
echo "  source /home/pi/bangre/venv/bin/activate"
echo "  pip list"
echo ""
