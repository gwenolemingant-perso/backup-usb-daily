#!/usr/bin/env bats

@test "script aborts if mountpoint is root" {
  run bash -c '
    export MOUNT_POINT=/
    ./bin/backup_usb_daily.sh -t
  '

  [ "$status" -ne 0 ]
}
