#!/usr/bin/env bats
# scripts/norns-bootlog: the boot diagnostics dump on the boot partition.

load ../helpers

setup() {
  W=$(mktemp -d)
  D=$W/boot; mkdir "$D"
  STATE=$W/rotated
  printf 'a=1\n# BEGIN norns-codec\n[pi4]\ndtoverlay=norns-snd-cs4270\n# END norns-codec\n' > "$D/config.txt"
}
teardown() { rm -rf "$W"; }

bootlog() { "$REPO_ROOT/scripts/norns-bootlog" --dir "$D" --state "$STATE"; }

@test "writes every section, and the codec block" {
  run bootlog
  [ "$status" -eq 0 ]
  l=$D/norns-boot.log
  for s in 'uname -a' 'systemctl --failed' 'systemctl status' 'journalctl -b -p warning' \
           'journalctl -b -1' 'ip -brief addr' 'ss -tlnp' 'device nodes' 'aplay -l' \
           'lsmod' 'df -h /' 'config.txt from # BEGIN norns-codec'; do
    grep -q "^===== $s" "$l" || { echo "missing: $s"; return 1; }
  done
  grep -qx 'dtoverlay=norns-snd-cs4270' "$l"
  ! grep -qx 'a=1' "$l" || false
  [ -z "$(ls -A "$D" | grep '^\.norns-boot')" ]
}
@test "first run of a boot keeps the previous boot's log; later runs don't" {
  echo old > "$D/norns-boot.log"
  bootlog
  [ "$(cat "$D/norns-boot.prev.log")" = old ]
  echo same-boot > "$D/norns-boot.log"
  bootlog                                  # same boot: state file exists
  [ "$(cat "$D/norns-boot.prev.log")" = old ]
  grep -q '^norns boot log' "$D/norns-boot.log"
}
@test "size is capped" {
  NORNS_BOOTLOG_MAX=500 run bootlog
  [ "$status" -eq 0 ]
  [ "$(wc -c < "$D/norns-boot.log")" -le 500 ]
}
@test "never fails: missing directory, failing commands" {
  run "$REPO_ROOT/scripts/norns-bootlog" --dir "$W/nonexistent" --state "$STATE"
  [ "$status" -eq 0 ]
  mkdir "$W/bin"
  for c in systemctl journalctl ip ss aplay lsmod df; do
    printf '#!/bin/sh\nexit 3\n' > "$W/bin/$c"; chmod +x "$W/bin/$c"
  done
  PATH=$W/bin:$PATH run bootlog
  [ "$status" -eq 0 ]
  grep -q '(exit 3)' "$D/norns-boot.log"
}
