#!/bin/bash
set -u

########################################
# CHARGEMENT CONFIG
########################################
CONFIG_FILE="/etc/backup_usb_daily.conf"

# Valeurs par défaut (fallback)
SOURCE_DIR="/srv"
BACKUP_SUBDIR="backup"
MOUNT_POINT="/mnt/backup"
DEVICE_UUID=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
MAX_MONTHS=5
LOW_SPACE_PERCENT=90
MIN_DISK_GB=10
TEST_MODE=false

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

########################################
# PARAMÈTRES CLI (tests unitaires)
########################################
DEFAULT_DATE=$(date +%Y-%m-%d)
CUSTOM_DATE="$DEFAULT_DATE"

while getopts "s:b:d:t" opt; do
  case $opt in
    s) SOURCE_DIR="$OPTARG" ;;
    b) BACKUP_SUBDIR="$OPTARG" ;;
    d) CUSTOM_DATE="$OPTARG" ;;
    t) TEST_MODE=true ;;
    *) exit 1 ;;
  esac
done

########################################
# VARIABLES
########################################
HOSTNAME=$(hostname)
TODAY="$CUSTOM_DATE"
YEAR_MONTH=$(date -d "$TODAY" +%Y-%m)

BACKUP_ROOT="$MOUNT_POINT/$BACKUP_SUBDIR"
BACKUP_MONTH_DIR="$BACKUP_ROOT/$YEAR_MONTH"
BACKUP_DAY_DIR="$BACKUP_MONTH_DIR/$TODAY"

BACKUP_STATUS="OK"
LOG_FILE="/var/log/backup.log"

########################################
# FONCTIONS
########################################
log() {
  echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$1" >/dev/null
}

########################################
# DÉBUT
########################################
log "===== BACKUP DÉMARRÉ ====="
log "Mode test : $TEST_MODE"

########################################
# ESPACE DISQUE
########################################
USED=$(df -P "$MOUNT_POINT" | awk 'NR==2{gsub("%","",$5);print $5}')
ROOT_USED=$(df -P / | awk 'NR==2{gsub("%","",$5);print $5}')

[ "$USED" -ge "$LOW_SPACE_PERCENT" ] && \
send_telegram "⚠️ [$HOSTNAME] Disque backup presque plein: ${USED}%"

[ "$ROOT_USED" -ge "$LOW_SPACE_PERCENT" ] && \
send_telegram "⚠️ [$HOSTNAME] Disque système presque plein: ${ROOT_USED}%"

# Définition des périphériques pour le contrôle dmesg
MP_DEV=$(df -P "$MOUNT_POINT" | awk 'NR==2{print $1}')
ROOT_DEV=$(df -P / | awk 'NR==2{print $1}')

########################################
# BACKUP RSYNC
########################################
mkdir -p "$BACKUP_MONTH_DIR"

LAST_BACKUP=$(find "$BACKUP_MONTH_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)

log "last backup : $LAST_BACKUP / month dir : $BACKUP_MONTH_DIR"

if [ -n "$LAST_BACKUP" ] && [ "$LAST_BACKUP" != "$BACKUP_DAY_DIR" ]; then
  LINK_DEST="--link-dest=$LAST_BACKUP"
else
  LINK_DEST=""
fi

log "rsync --link-dest utilisé : $LINK_DEST"

mkdir -p "$BACKUP_DAY_DIR"

RSYNC_CMD="rsync -a  --no-perms --no-owner --no-group --delete $LINK_DEST \"$SOURCE_DIR/\" \"$BACKUP_DAY_DIR\" >> \"$LOG_FILE\" 2>&1"

log "$RSYNC_CMD"
eval "$RSYNC_CMD"

########################################
# ROTATION
########################################
cd "$BACKUP_ROOT" || exit
ls -1d ????-?? 2>/dev/null | sort | head -n -"$MAX_MONTHS" | xargs -r rm -rf

########################################
# SMART / DMesg Vérification
########################################
SMART_MSG=""

# Fonction de contrôle disque via dmesg
check_disk_errors() {
    local disk_dev="$1"
    SMART_MSG+="\n==== 🔍 Vérification erreurs disque $(basename $disk_dev) ====\n"
    errors=$(dmesg | grep -i $(basename $disk_dev) | grep -Ei "error|fail|i/o|critical")
    if [ -n "$errors" ]; then
        SMART_MSG+="$errors\n"
    else
        SMART_MSG+="Aucune erreur détectée dans les logs.\n"
    fi
}

# On exécute le contrôle système et backup systématiquement
check_disk_errors "$ROOT_DEV"
check_disk_errors "$MP_DEV"

########################################
# FIN
########################################
EMOJI=$([ "$BACKUP_STATUS" = "OK" ] && echo "✅" || echo "🚨")
MESSAGE=$(printf "%b" \
"$EMOJI [$HOSTNAME] Backup $BACKUP_STATUS\nDate: $TODAY\nSource: $SOURCE_DIR\nCible: $BACKUP_ROOT\nUsage backup: ${USED}%\nUsage système: ${ROOT_USED}%\n$SMART_MSG")

send_telegram "$MESSAGE"
log "===== BACKUP FINI ($BACKUP_STATUS) ====="
