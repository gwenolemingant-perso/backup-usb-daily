#!/usr/bin/env bats

@test "backup directory is created" {
  TMP_SRC=$(mktemp -d)
  TMP_DST=$(mktemp -d)

  echo "hello" > "$TMP_SRC/file.txt"

  run ./bin/backup_usb_daily.sh \
    -s "$TMP_SRC" \
    -b "$(basename "$TMP_DST")" \
    -t

  [ "$status" -eq 0 ]

  TODAY=$(date +%Y-%m-%d)
  YEAR_MONTH=$(date +%Y-%m)

  [ -f "/mnt/backup_usb_daily/$(basename "$TMP_DST")/$YEAR_MONTH/$TODAY/file.txt" ]
}
