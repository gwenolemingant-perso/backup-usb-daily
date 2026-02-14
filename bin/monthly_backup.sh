#!/bin/bash

source ./backup_common.sh
set -euo pipefail

CONFIG_FILE="/etc/monthly_backup.conf"

#########################################
# Paramètres
#########################################
CIFS_SHARE=""
MOUNT_POINT_SOURCE=""
MOUNT_POINT_DESTINATION=""
CIFS_USER=""
CIFS_PASS=""

BASE_SOURCE=""
BASE_DESTINATION=""

BACKUP_STATUS="OK"
LOG_FILE="$HOME/monthly_backup.log"

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

#########################################
# Variables date
#########################################
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
YEAR_MONTH="${YEAR}-${MONTH}"
FULL_DATE="${YEAR}-${MONTH}-${DAY}"
SOURCE="${BASE_SOURCE}/${YEAR_MONTH}/${FULL_DATE}"


if ! mountpoint -q "$MOUNT_POINT_DESTINATION"; then
    log "📌 Montage du partage destination sur $MOUNT_POINT_DESTINATION"
    CMD="mkdir -p \"$MOUNT_POINT_DESTINATION\""
    log "$CMD"
    eval "$CMD"

    CMD="mount $DEVICE_DESTINATION \"$MOUNT_POINT_DESTINATION\""
    log "$CMD"
    eval "$CMD"
else
    log "ℹ️ $MOUNT_POINT_DESTINATION déjà monté"
fi

#########################################
# Vérifications du dossier destination
#########################################

if [ ! -d "$BASE_DESTINATION" ]; then
    log "❌ Destination inexistante : $BASE_DESTINATION"
    exit 1
fi

#########################################
# Synchronisation
#########################################
log "===== $(date) ====="
log "Source      : $BASE_SOURCE"
log "Destination : $BASE_DESTINATION"
log ""

RSYNC_CMD="rsync -aHAX --numeric-ids --delete --human-readable --info=progress2 --stats \"$SRV_USER@$SRV_IP:${SOURCE}/\" \"${BASE_DESTINATION}/\""
log "$RSYNC_CMD"
eval "$RSYNC_CMD" || BACKUP_STATUS="ERROR"

log ""
log "✅ Synchronisation terminée"
echo "" >> "$LOG_FILE"

EMOJI=$([ "$BACKUP_STATUS" = "OK" ] && echo "✅" || echo "🚨")
MESSAGE=$(printf "%b" \
"$EMOJI Backup externe $BACKUP_STATUS
Date : $FULL_DATE
Source : $BASE_SOURCE
Cible : $BASE_DESTINATION")

send_telegram "$MESSAGE"

exit 0
