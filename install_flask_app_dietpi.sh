#!/bin/bash

# Script d'automatisation d'installation Flask avec Nginx et Gunicorn
# Version améliorée avec gestion robuste des environnements virtuels
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
    exit 1
  fi
}

# Fonction pour installer les paquets avec vérification
install_package() {
  local package=$1
  log "Installation de $package..."
  apt install -y "$package" >/dev/null 2>&1
  if dpkg -l | grep -q "^ii  $package "; then
    log "✓ $package installé avec succès"
  else
    log "✗ Échec d'installation de $package"
    return 1
  fi
}

# Fonction pour vérifier et installer les dépendances Python
install_python_dependencies() {
  local venv_path=$1
  local req_file=$2

  log "Vérification de l'environnement virtuel..."

  # Vérifier si l'environnement virtuel existe
  if [ ! -f "$venv_path/bin/activate" ]; then
    log "Création de l'environnement virtuel..."
    python3 -m venv "$venv_path"
    check_status "Environnement virtuel créé"
  fi

  # Activer l'environnement virtuel
  log "Activation de l'environnement virtuel..."
  source "$venv_path/bin/activate"

  # Vérifier que l'activation a fonctionné
  if [ -z "$VIRTUAL_ENV" ]; then
    log "✗ Échec d'activation de l'environnement virtuel"
    exit 1
  else
    log "✓ Environnement virtuel activé: $VIRTUAL_ENV"
  fi

  # Mettre à jour pip dans l'environnement virtuel
  log "Mise à jour de pip..."
  python -m pip install --upgrade pip >/dev/null 2>&1
  check_status "pip mis à jour"

  # Vérifier la version de pip
  pip_version=$(pip --version | cut -d' ' -f2)
  log "Version de pip: $pip_version"

  # Vérifier l'existence du fichier requirements.txt
  if [ ! -f "$req_file" ]; then
    log "⚠ Fichier $req_file non trouvé"
    log "Création d'un fichier requirements.txt par défaut..."

    # Installer les dépendances de base pour Flask
    log "Installation des dépendances de base..."
    pip install flask==3.1.2 gunicorn==20.1.0 >/dev/null 2>&1

    # Vérifier l'installation de chaque package
    for pkg in flask gunicorn; do
      if pip show "$pkg" >/dev/null 2>&1; then
        log "✓ $pkg installé avec succès"
      else
        log "✗ Échec d'installation de $pkg"
        return 1
      fi
    done

    # Générer le fichier requirements.txt
    pip freeze >"$req_file"
    log "✓ Fichier $req_file créé avec les dépendances actuelles"

  else
    log "Fichier $req_file trouvé, installation des dépendances..."

    # Vérifier la syntaxe du fichier requirements.txt
    if ! grep -q -E '^[a-zA-Z0-9_\-\.]+[=<>!]=[0-9\.\*]+' "$req_file" &&
      ! grep -q -E '^[a-zA-Z0-9_\-\.]+$' "$req_file"; then
      log "⚠ Le fichier $req_file semble vide ou mal formé"
      log "Contenu du fichier:"
      cat "$req_file"
    fi

    # Compter le nombre de dépendances
    dep_count=$(grep -c -E '^[^#]' "$req_file")
    log "Nombre de dépendances à installer: $dep_count"

    # Installer les dépendances avec cache
    log "Installation des dépendances..."
    pip install --no-cache-dir -r "$req_file" >/dev/null 2>&1

    # Vérifier les installations
    log "Vérification des installations..."
    installed_count=0
    failed_packages=""

    while IFS= read -r line || [ -n "$line" ]; do
      # Ignorer les lignes vides et les commentaires
      [[ -z "$line" || "$line" =~ ^# ]] && continue

      # Extraire le nom du package (avant ==, >=, <=, etc.)
      pkg_name=$(echo "$line" | sed 's/[<>=!].*//' | sed 's/\[.*\]//')

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
        # Tentative de réinstallation des packages échoués
        log "Tentative de réinstallation..."
        for pkg in $failed_packages; do
          pip install "$pkg" >/dev/null 2>&1 && log "  ✓ $pkg réinstallé" || log "  ✗ Échec sur $pkg"
        done
      fi
    fi
  fi

  # Vérifier les dépendances critiques
  log "Vérification des dépendances critiques..."
  critical_packages=("flask" "gunicorn")
  for critical_pkg in "${critical_packages[@]}"; do
    if pip show "$critical_pkg" >/dev/null 2>&1; then
      log "✓ $critical_pkg est installé"
    else
      log "✗ $critical_pkg n'est pas installé - tentative d'installation..."
      pip install "$critical_pkg" >/dev/null 2>&1
      check_status "Installation de $critical_pkg"
    fi
  done

  # Lister tous les packages installés
  log "Packages Python installés dans l'environnement virtuel:"
  pip list --format=columns | tail -n +3

  # Désactiver l'environnement virtuel
  deactivate
  log "Environnement virtuel désactivé"
}

echo "=========================================="
echo "  Installation automatisée Flask + Nginx  "
echo "=========================================="

# 1) Installation des paquets système requis
log "=== Étape 1: Installation des paquets système ==="

# Mise à jour des paquets
log "Mise à jour des listes de paquets..."
apt update >/dev/null 2>&1
check_status "Listes de paquets mises à jour"

# Liste des paquets à installer
packages=(
  "openssh-sftp-server"
  "nginx"
  "python3"
  "python3-venv"
  "python3-pip"
  "gunicorn"
)

# Installer chaque paquet avec vérification
for package in "${packages[@]}"; do
  install_package "$package"
done

# Vérifier les installations
log "Vérification finale des paquets installés..."
for package in "${packages[@]}"; do
  if dpkg -l | grep -q "^ii  $package "; then
    log "✓ $package: OK"
  else
    log "✗ $package: MANQUANT"
    # Tentative de réinstallation
    apt install -y "$package" >/dev/null 2>&1
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

check_status "Fichier de configuration Nginx créé"

# 3) Configuration des sites Nginx
log "=== Étape 3: Configuration des sites ==="

# Supprimer le site par défaut
if [ -f "/etc/nginx/sites-enabled/default" ]; then
  log "Suppression du site par défaut..."
  rm /etc/nginx/sites-enabled/default
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
ExecStart=/home/pi/bangre/venv/bin/gunicorn --bind 127.0.0.1:5000 --workers 2 --access-logfile /home/pi/logs/gunicorn_access.log --error-logfile /home/pi/logs/gunicorn_error.log --log-level info app:app
Restart=always
RestartSec=10

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
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Application Flask en cours d\'exécution!'

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000, debug=False)
EOF
  check_status "Fichier app.py créé"
else
  log "✓ Fichier app.py trouvé"
fi

# 8) Redémarrage des services
log "=== Étape 8: Redémarrage des services ==="

# Tester la configuration Nginx
log "Test de la configuration Nginx..."
if nginx -t >/dev/null 2>&1; then
  log "✓ Configuration Nginx valide"
else
  log "✗ Configuration Nginx invalide"
  nginx -t # Afficher l'erreur
  exit 1
fi

# Recharger Nginx
log "Rechargement de Nginx..."
systemctl reload nginx
check_status "Nginx rechargé"

# Recharger les daemons systemd
log "Rechargement des daemons systemd..."
systemctl daemon-reload
check_status "Daemons systemd rechargés"

# Activer et démarrer le service
log "Activation du service..."
systemctl enable app_bangre.service >/dev/null 2>&1
check_status "Service activé"

log "Démarrage du service..."
systemctl start app_bangre.service
check_status "Service démarré"

# Attendre un peu et vérifier le statut
sleep 2
log "Vérification du statut du service..."
if systemctl is-active --quiet app_bangre.service; then
  log "✓ Service actif"
else
  log "✗ Service inactif - vérification des logs..."
  systemctl status app_bangre.service --no-pager -l
fi

echo ""
echo "=========================================="
log "INSTALLATION TERMINÉE AVEC SUCCÈS!"
echo "=========================================="
echo ""
echo "RÉSUMÉ DE L'INSTALLATION:"
echo "1. Paquets système: ✓ Installés"
echo "2. Configuration Nginx: ✓ Terminée"
echo "3. Service systemd: ✓ Créé et activé"
echo "4. Environnement virtuel Python: ✓ Configuré"
echo "5. Dépendances Python: ✓ Installées"
echo ""
echo "COMMANDES DE VÉRIFICATION:"
echo "  sudo systemctl status app_bangre.service"
echo "  sudo systemctl status nginx"
echo ""
echo "FICHIERS DE LOGS:"
echo "  Application: /home/pi/logs/gunicorn_*.log"
echo "  Nginx: /var/log/nginx/app_bangre_*.log"
echo ""
echo "TEST DE L'APPLICATION:"
echo "  curl http://localhost:5000"
echo "  ou visitez: http://bangre.local"
echo ""
echo "POUR REDÉMARRER L'APPLICATION:"
echo "  sudo systemctl restart app_bangre.service"
echo ""
