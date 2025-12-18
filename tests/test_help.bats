#!/usr/bin/env bats

@test "invalid option returns error" {
  run ./bin/backup_usb_daily.sh -z
  [ "$status" -ne 0 ]
}
