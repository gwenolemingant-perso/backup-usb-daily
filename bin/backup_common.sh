#!/bin/bash

log() {
  echo "[$(date '+%F %T')] $1" | tee -a "$LOG_FILE"
}

send_telegram() {
  [ -z "$TELEGRAM_BOT_TOKEN" ] && return
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$1" >/dev/null
}
