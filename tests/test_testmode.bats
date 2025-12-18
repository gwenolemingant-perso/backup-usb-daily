#!/usr/bin/env bats

@test "backup runs in test mode without mount" {
  run ./bin/backup_usb_daily.sh -s /tmp -b test_backup -t
  [ "$status" -eq 0 ]
}
