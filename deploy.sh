#!/bin/bash
set -e

APP_NAME="backup-usb-daily"
INSTALL_DIR="/opt/$APP_NAME"
BIN_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"

echo "🚀 Déploiement de $APP_NAME"

########################################
# Vérifications
########################################
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ce script doit être exécuté en root"
  exit 1
fi

########################################
# Création des dossiers
########################################
echo "📁 Création des répertoires..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/config"

########################################
# Copie des fichiers
########################################
echo "📦 Copie des fichiers..."
cp -r bin lib "$INSTALL_DIR/"
cp config/backup.conf "$INSTALL_DIR/config/backup.conf.example"

########################################
# Droits
########################################
echo "🔐 Permissions..."
chmod +x "$INSTALL_DIR/bin/backup-usb-daily.sh"

########################################
# Symlink binaire
########################################
echo "🔗 Création du lien symbolique..."
ln -sf "$INSTALL_DIR/bin/backup-usb-daily.sh" "$BIN_DIR/backup-usb-daily"

########################################
# systemd
########################################
if [ -f systemd/backup-usb-daily.service ]; then
  echo "⚙️ Installation systemd..."
  cp systemd/*.service "$SERVICE_DIR/"
  cp systemd/*.timer "$SERVICE_DIR/"
  systemctl daemon-reload
  systemctl enable backup-usb-daily.timer
fi

########################################
# Fin
########################################
echo "✅ Déploiement terminé"
echo
echo "➡️ Copier la config :"
echo "   cp $INSTALL_DIR/config/backup.conf.example $INSTALL_DIR/config/backup.conf"
echo
echo "➡️ Tester :"
echo "   backup-usb-daily --test"
