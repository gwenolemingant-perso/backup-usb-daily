#!/usr/bin/env bats

@test "rotation keeps only MAX_MONTHS" {
  TMP_DST=$(mktemp -d)
  export MAX_MONTHS=2

  for m in 2024-01 2024-02 2024-03; do
    mkdir -p "$TMP_DST/$m"
  done

  run bash -c "
    cd '$TMP_DST' &&
    ls -1d ????-?? | sort | head -n -$MAX_MONTHS | xargs -r rm -rf
  "

  [ "$(ls -1 "$TMP_DST" | wc -l)" -eq 2 ]
}
