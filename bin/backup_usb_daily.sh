#!/bin/bash
set -u

########################################
# CHARGEMENT CONFIG
########################################
CONFIG_FILE="/etc/backup_usb_daily.conf"

# Valeurs par défaut (fallback)
SOURCE_DIR="/srv"
BACKUP_SUBDIR="backup"
MOUNT_POINT="/mnt/backup_usb_daily"
DEVICE_UUID=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
MAX_MONTHS=5
LOW_SPACE_PERCENT=90
MIN_DISK_GB=10
TEST_MODE=false

[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

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
LOG_FILE="/var/log/backup_daily.log"

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

cleanup() {
  $TEST_MODE && return
  cd / || exit
  mountpoint -q "$MOUNT_POINT" && sudo umount "$MOUNT_POINT" || true
}
trap cleanup EXIT

########################################
# DÉBUT
########################################
log "===== BACKUP DÉMARRÉ ====="
log "Mode test : $TEST_MODE"

########################################
# MONTAGE
########################################
if ! $TEST_MODE; then
  if ! mountpoint -q "$MOUNT_POINT"; then
    lsblk -o UUID | grep -q "${DEVICE_UUID#UUID=}" \
      && sudo mount "$DEVICE_UUID" "$MOUNT_POINT" \
      || { send_telegram "🚨 [$HOSTNAME] Disque USB absent"; exit 1; }
  fi
fi

########################################
# SÉCURITÉ /
########################################
MP_DEV=$(df -P "$MOUNT_POINT" | awk 'NR==2{print $1}')
ROOT_DEV=$(df -P / | awk 'NR==2{print $1}')
[ "$MP_DEV" = "$ROOT_DEV" ] && exit 1

########################################
# ESPACE DISQUE
########################################
USED=$(df -P "$MOUNT_POINT" | awk 'NR==2{gsub("%","",$5);print $5}')
[ "$USED" -ge "$LOW_SPACE_PERCENT" ] &&
send_telegram "⚠️ [$HOSTNAME] Disque presque plein: ${USED}%"

########################################
# BACKUP RSYNC
########################################
mkdir -p "$BACKUP_MONTH_DIR"
LAST_BACKUP=$(ls -1d "$BACKUP_MONTH_DIR"/* 2>/dev/null | tail -n 1)
[ -n "$LAST_BACKUP" ] && LINK_DEST="--link-dest=$LAST_BACKUP" || LINK_DEST=""

mkdir -p "$BACKUP_DAY_DIR"
rsync -a --delete $LINK_DEST "$SOURCE_DIR/" "$BACKUP_DAY_DIR" >> "$LOG_FILE" 2>&1 || BACKUP_STATUS="KO"

########################################
# ROTATION
########################################
cd "$BACKUP_ROOT" || exit
ls -1d ????-?? 2>/dev/null | sort | head -n -"$MAX_MONTHS" | xargs -r rm -rf

########################################
# FIN
########################################
EMOJI=$([ "$BACKUP_STATUS" = "OK" ] && echo "✅" || echo "🚨")
MESSAGE=$(printf "%b" \
"$EMOJI [$HOSTNAME] Backup $BACKUP_STATUS\nDate: $TODAY\nSource: $SOURCE_DIR\nCible: $BACKUP_ROOT\nUsage: ${USED}%")

send_telegram "$MESSAGE"
log "===== BACKUP FINI ($BACKUP_STATUS) ====="
