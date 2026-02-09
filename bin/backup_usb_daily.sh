#!/bin/bash
set -u

########################################
# CHARGEMENT CONFIG
########################################
CONFIG_FILE="/etc/backup_usb_daily.conf"

# Valeurs par défaut
SOURCE_DIR="/srv"
BACKUP_SUBDIR="backup"
MOUNT_POINT="/mnt/backup"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
LOW_SPACE_PERCENT=90
TEST_MODE=false

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

########################################
# PARAMÈTRES CLI
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

LOG_FILE="/var/log/backup.log"
BACKUP_STATUS="OK"

########################################
# FONCTIONS
########################################
log() {
  echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
  [ -z "$TELEGRAM_BOT_TOKEN" ] && return
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$1" >/dev/null
}

########################################
# DÉBUT
########################################
log "===== BACKUP DÉMARRÉ ====="

########################################
# ESPACE DISQUE
########################################
USED=$(df -P "$MOUNT_POINT" | awk 'NR==2{gsub("%","",$5);print $5}')
ROOT_USED=$(df -P / | awk 'NR==2{gsub("%","",$5);print $5}')

[ "$USED" -ge "$LOW_SPACE_PERCENT" ] && \
send_telegram "⚠️ [$HOSTNAME] Disque backup presque plein: ${USED}%"

[ "$ROOT_USED" -ge "$LOW_SPACE_PERCENT" ] && \
send_telegram "⚠️ [$HOSTNAME] Disque système presque plein: ${ROOT_USED}%"

MP_DEV=$(df -P "$MOUNT_POINT" | awk 'NR==2{print $1}')
ROOT_DEV=$(df -P / | awk 'NR==2{print $1}')

########################################
# BACKUP RSYNC
########################################
mkdir -p "$BACKUP_MONTH_DIR"

LAST_BACKUP=$(find "$BACKUP_MONTH_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)

if [ -n "$LAST_BACKUP" ] && [ "$LAST_BACKUP" != "$BACKUP_DAY_DIR" ]; then
  LINK_DEST="--link-dest=$LAST_BACKUP"
else
  LINK_DEST=""
fi

mkdir -p "$BACKUP_DAY_DIR"

RSYNC_CMD="rsync -a --no-perms --no-owner --no-group --delete \
$LINK_DEST \"$SOURCE_DIR/\" \"$BACKUP_DAY_DIR\" >> \"$LOG_FILE\" 2>&1"

log "$RSYNC_CMD"
eval "$RSYNC_CMD" || BACKUP_STATUS="ERROR"

########################################
# ROTATION BACKUP (1 MOIS)
########################################
cd "$BACKUP_ROOT" || exit
ls -1d ????-?? 2>/dev/null | grep -v "$YEAR_MONTH" | xargs -r rm -rf

########################################
# ARCHIVE MENSUELLE (AVEC TEST INTÉGRITÉ)
########################################
ARCHIVE_DIR="$BACKUP_ROOT/monthly_archive"
mkdir -p "$ARCHIVE_DIR"

MONTH_ARCHIVE="$ARCHIVE_DIR/$YEAR_MONTH-backup.tar.gz"
TMP_ARCHIVE="$MONTH_ARCHIVE.tmp"

# Suppression des anciennes archives
find "$ARCHIVE_DIR" -type f -not -name "$(basename "$MONTH_ARCHIVE")" -exec rm -f {} \;

if [ ! -f "$MONTH_ARCHIVE" ]; then
    log "Création archive mensuelle temporaire : $TMP_ARCHIVE"

    tar -czf "$TMP_ARCHIVE" -C "$BACKUP_ROOT" "$YEAR_MONTH" >> "$LOG_FILE" 2>&1
    TAR_RC=$?

    if [ $TAR_RC -ne 0 ]; then
        log "❌ Erreur création archive"
        rm -f "$TMP_ARCHIVE"
        BACKUP_STATUS="ERROR"
        send_telegram "🚨 [$HOSTNAME] Échec création archive mensuelle $YEAR_MONTH"
    else
        log "Test intégrité archive…"
        tar -tzf "$TMP_ARCHIVE" >/dev/null 2>&1
        TEST_RC=$?

        if [ $TEST_RC -eq 0 ]; then
            mv "$TMP_ARCHIVE" "$MONTH_ARCHIVE"
            log "✅ Archive mensuelle validée"
            send_telegram "📦 [$HOSTNAME] Archive mensuelle $YEAR_MONTH créée et vérifiée"
        else
            log "❌ Archive corrompue"
            rm -f "$TMP_ARCHIVE"
            BACKUP_STATUS="ERROR"
            send_telegram "🚨 [$HOSTNAME] Archive mensuelle $YEAR_MONTH CORROMPUE"
        fi
    fi
else
    log "Archive mensuelle déjà existante"
fi

########################################
# DMESG DISQUES
########################################
SMART_MSG=""

check_disk_errors() {
    local dev="$1"
    SMART_MSG+="\n==== Vérification $(basename "$dev") ====\n"
    errors=$(dmesg | grep -i "$(basename "$dev")" | grep -Ei "error|fail|i/o|critical")
    [ -n "$errors" ] && SMART_MSG+="$errors\n" || SMART_MSG+="Aucune erreur détectée\n"
}

check_disk_errors "$ROOT_DEV"
check_disk_errors "$MP_DEV"

########################################
# FIN
########################################
EMOJI=$([ "$BACKUP_STATUS" = "OK" ] && echo "✅" || echo "🚨")
MESSAGE=$(printf "%b" \
"$EMOJI [$HOSTNAME] Backup $BACKUP_STATUS
Date: $TODAY
Source: $SOURCE_DIR
Cible: $BACKUP_ROOT
Usage backup: ${USED}%
Usage système: ${ROOT_USED}%
$SMART_MSG")

send_telegram "$MESSAGE"
log "===== BACKUP TERMINÉ ($BACKUP_STATUS) ====="
