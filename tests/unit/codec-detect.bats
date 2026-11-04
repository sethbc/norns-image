#!/usr/bin/env bats
# scripts/norns-codec-detect: finds the shield's codec on I2C and rewrites the
# managed block of config.txt.

load ../helpers

setup() {
  W=$(mktemp -d)
  FIXTURE=$W/fixture.txt
  CFG=$W/config.txt
  LOG=$W/log
  : > "$LOG"
  export LOG
  cat > "$FIXTURE" <<'TXT'
# before
dtparam=i2c_arm=on
[all]
# BEGIN norns-codec
# END norns-codec
dtoverlay=norns-buttons-encoders
# after
TXT
  cp "$FIXTURE" "$CFG"
  FAKEPROBE=$W/probe
  cat > "$FAKEPROBE" <<'SH'
#!/bin/bash
echo "probe $1" >> "$LOG"
for a in $FAKE_I2C; do [ "$a" = "$1" ] && exit 0; done
exit 1
SH
  FAKERESET=$W/reset
  cat > "$FAKERESET" <<'SH'
#!/bin/bash
echo "reset $1" >> "$LOG"
SH
  chmod +x "$FAKEPROBE" "$FAKERESET"
  export NORNS_CODEC_RESET_DELAY=0 NORNS_CODEC_SETTLE=0 NORNS_CODEC_BUS_WAIT=1
  SYS=$W/sys; mkdir "$SYS"
  I2CDEV=$W/i2c-1; : > "$I2CDEV"
}

teardown() { rm -rf "$W"; }

detect() {
  "$REPO_ROOT/scripts/norns-codec-detect" --config "$CFG" --probe "$FAKEPROBE" --reset "$FAKERESET" --sysfs "$SYS" --i2c-dev "$I2CDEV"
}
block_has() { sed -n '/^# BEGIN norns-codec$/,/^# END norns-codec$/p' "$CFG" | grep -qxF "$1"; }
outside_block() { sed '/^# BEGIN norns-codec$/,/^# END norns-codec$/d' "$1"; }

@test "writes cs4270 block and exits 10" {
  FAKE_I2C=0x48 run detect
  [ "$status" -eq 10 ]
  block_has '[pi4]'; block_has '[pi5]'; block_has '[all]'
  block_has dtoverlay=norns-snd-cs4270
  block_has dtoverlay=norns-snd-cs4270-pi5
}
@test "second run is a no-op (no reboot loop)" {
  FAKE_I2C=0x48 detect || true
  before=$(sha256sum "$CFG")
  FAKE_I2C=0x48 run detect
  [ "$status" -eq 0 ]
  [ "$(sha256sum "$CFG")" = "$before" ]
}
@test "cs4271 replaces a stale cs4270 block" {
  FAKE_I2C=0x48 detect || true
  FAKE_I2C=0x10 run detect
  [ "$status" -eq 10 ]
  block_has dtoverlay=norns-snd-cs4271
  ! grep -q cs4270 "$CFG"
}
@test "nothing found leaves file untouched" {
  before=$(sha256sum "$CFG")
  FAKE_I2C= run detect
  [ "$status" -eq 2 ]
  [ "$(sha256sum "$CFG")" = "$before" ]
  [[ "$output" == *"no codec"* ]]
}
@test "a PiSugar at 0x57/0x68 is ignored" {
  FAKE_I2C="0x57 0x68" run detect
  [ "$status" -eq 2 ]
  ! grep -qE 'probe 0x(57|68)' "$LOG"
}
@test "text outside markers preserved" {
  FAKE_I2C=0x10 detect || true
  diff <(outside_block "$CFG") <(outside_block "$FIXTURE")
}
@test "both found prefers cs4270 and warns" {
  FAKE_I2C="0x48 0x10" run detect
  [ "$status" -eq 10 ]
  block_has dtoverlay=norns-snd-cs4270
  [[ "$output" == *"both"* ]]
}
@test "no leftover temp files" {
  FAKE_I2C=0x48 detect || true
  [ "$(ls "$W" | grep -c config)" -eq 1 ]
}
@test "reset released before probing, released again after" {
  FAKE_I2C=0x48 detect || true
  [ "$(sed -n 1p "$LOG")" = "reset high" ]
  [ "$(grep -n '^probe' "$LOG" | head -1 | cut -d: -f1)" -gt 1 ]
  [ "$(tail -n1 "$LOG")" = "reset release" ]
}
@test "reset line is let go when nothing is found" {
  FAKE_I2C= run detect
  [ "$status" -eq 2 ]
  [ "$(sed -n 1p "$LOG")" = "reset high" ]
  [ "$(tail -n1 "$LOG")" = "reset release" ]
  [ "$(grep -c '^reset' "$LOG")" -eq 2 ]
}
@test "appends a block when the file has no markers" {
  printf 'a=1\n' > "$CFG"
  FAKE_I2C=0x10 run detect
  [ "$status" -eq 10 ]
  block_has dtoverlay=norns-snd-cs4271
  [ "$(head -n1 "$CFG")" = "a=1" ]
}
@test "default reset drives GPIO17 high, then restores its earlier state" {
  mkdir "$W/bin"
  cat > "$W/bin/pinctrl" <<'SH'
#!/bin/bash
echo "pinctrl $*" >> "$LOG"
[ "$1" = get ] && echo "17: ip    pd | lo // GPIO17 = input"
exit 0
SH
  chmod +x "$W/bin/pinctrl"
  FAKE_I2C= PATH=$W/bin:$PATH run "$REPO_ROOT/scripts/norns-codec-detect" --config "$CFG" --probe "$FAKEPROBE" --sysfs "$SYS" --i2c-dev "$I2CDEV"
  [ "$status" -eq 2 ]
  grep -qx 'pinctrl set 17 op dh' "$LOG"
  [ "$(tail -n1 "$LOG")" = "pinctrl set 17 ip pd" ]
}
@test "bus that never appears: exit 2, file untouched, GPIO17 never taken" {
  rm "$I2CDEV"
  before=$(sha256sum "$CFG")
  FAKE_I2C=0x48 run detect
  [ "$status" -eq 2 ]
  [ "$(sha256sum "$CFG")" = "$before" ]
  [[ "$output" == *"did not appear"* ]]
  [ "$(grep -c '^reset high' "$LOG")" -eq "$(grep -c '^reset release' "$LOG")" ]
  ! grep -q '^probe' "$LOG"
}
@test "bus that appears late is waited for" {
  rm "$I2CDEV"
  ( sleep 0.5; : > "$I2CDEV" ) &
  FAKE_I2C=0x48 run detect
  [ "$status" -eq 10 ]
}
@test "bound codec driver: present, no GPIO17, no I2C" {
  mkdir -p "$SYS/1-0010"; ln -s /nonexistent "$SYS/1-0010/driver"
  # the link dangles in the fixture; -e would miss it
  rm "$SYS/1-0010/driver"; mkdir "$SYS/1-0010/driver"
  FAKE_I2C= run detect
  [ "$status" -eq 10 ]
  block_has dtoverlay=norns-snd-cs4271
  [ ! -s "$LOG" ]
  FAKE_I2C= run detect
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}
@test "bound cs4270 driver with correct block: exit 0 even without a bus" {
  FAKE_I2C=0x48 detect || true
  rm "$I2CDEV"; : > "$LOG"
  mkdir -p "$SYS/1-0048/driver"
  FAKE_I2C= run detect
  [ "$status" -eq 0 ]
  [ ! -s "$LOG" ]
}
@test "default reset leaves GPIO17 alone when it is already driven high" {
  mkdir "$W/bin"
  cat > "$W/bin/pinctrl" <<'SH'
#!/bin/bash
echo "pinctrl $*" >> "$LOG"
[ "$1" = get ] && echo "17: op dh pn | hi // GPIO17 = output"
exit 0
SH
  chmod +x "$W/bin/pinctrl"
  FAKE_I2C=0x48 PATH=$W/bin:$PATH run "$REPO_ROOT/scripts/norns-codec-detect" --config "$CFG" --probe "$FAKEPROBE" --sysfs "$SYS" --i2c-dev "$I2CDEV"
  [ "$status" -eq 10 ]
  ! grep -q 'pinctrl set' "$LOG"
}
