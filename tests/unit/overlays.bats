#!/usr/bin/env bats
# Device tree overlays for the norns shield on the Pi 4 (overlays/*.dts):
# the CS4270 and CS4271 sound cards, and the keys and encoders, with the
# shield's pins as defaults and the node names matron's input paths need.

setup_file() {
  load ../helpers
  for f in "$REPO_ROOT"/overlays/*.dts; do
    dtc -q -@ -I dts -O dtb -o "$BATS_FILE_TMPDIR/$(basename "$f" -overlay.dts).dtbo" "$f" || true
  done
}

setup() {
  load ../helpers
  DTBO_DIR=$BATS_FILE_TMPDIR
}

# gpio cells of PROP on the node labelled LABEL in overlay NAME, as
# "pin flags" pairs, one per line (the phandle cells are dropped).
gpio_pins() {
  ov_get "$1" "$2" "${3:-gpios}" | tr ' ' '\n' | awk 'NR % 3 == 2 { p = $1 } NR % 3 == 0 { print p, $1 }'
}

@test "overlays compile without warnings" {
  for f in "$REPO_ROOT"/overlays/*.dts; do
    run dtc -@ -I dts -O dtb -o /dev/null "$f"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$f: $output"; false; }
  done
  for o in norns-snd-cs4270 norns-snd-cs4271 norns-buttons-encoders; do
    [ -s "$DTBO_DIR/$o.dtbo" ]
  done
}

@test "overlays are for the Pi 4" {
  for o in norns-snd-cs4270 norns-snd-cs4271 norns-buttons-encoders; do
    [ "$(fdtget "$(dtbo_path "$o")" / compatible)" = "brcm,bcm2711" ]
  done
}

@test "cs4270 at 0x48, card name" {
  o=$(dtbo norns-snd-cs4270)
  grep -q 'cirrus,cs4270' <<<"$o"
  grep -q 'reg = <0x00000048>' <<<"$o"
  grep -q 'snd-rpi-monome' <<<"$o"
  [ "$(ov_get norns-snd-cs4270 cs4270 compatible)" = "cirrus,cs4270" ]
  [ "$(ov_get norns-snd-cs4270 cs4270 reg)" = "72" ]
}

@test "cs4271 at 0x10, card name" {
  o=$(dtbo norns-snd-cs4271)
  grep -q 'cirrus,cs4271' <<<"$o"
  grep -q 'reg = <0x00000010>' <<<"$o"
  grep -q 'snd-rpi-monome' <<<"$o"
  [ "$(ov_get norns-snd-cs4271 cs4271 compatible)" = "cirrus,cs4271" ]
  [ "$(ov_get norns-snd-cs4271 cs4271 reg)" = "16" ]
}

@test "sound cards: simple-audio-card on i2s and i2c1, codec clock master" {
  for c in cs4270 cs4271; do
    f=$(dtbo_path "norns-snd-$c")
    [ "$(fdtget "$f" /fragment@0/__overlay__ compatible)" = "simple-audio-card" ]
    [ "$(fdtget "$f" /fragment@0/__overlay__ simple-audio-card,name)" = "snd-rpi-monome" ]
    # the card, the i2s controller and the i2c bus are the Pi 4 base DT's
    fdtget "$f" /__fixups__ sound | grep -q '/fragment@0:target:0'
    fdtget "$f" /__fixups__ i2s_clk_consumer | grep -q ':target:0'
    fdtget "$f" /__fixups__ i2c1 | grep -q ':target:0'
    link=/fragment@0/__overlay__/simple-audio-card,dai-link
    [ "$(fdtget "$f" "$link" format)" = "i2s" ]
    codec=$(fdtget "$f" "$link/codec" phandle)
    [ "$(fdtget "$f" "$link" bitclock-master)" = "$codec" ]
    [ "$(fdtget "$f" "$link" frame-master)" = "$codec" ]
    [ "$(fdtget "$f" "$link/codec" system-clock-frequency)" = "12288000" ]
  done
}

@test "codec reset on GPIO17, polarity as each driver expects" {
  # cs4270.c: logical 1 releases reset (active high); cs4271.c: logical 1
  # holds the chip in reset (active low).
  [ "$(gpio_pins norns-snd-cs4270 cs4270 reset-gpios)" = "17 0" ]
  [ "$(gpio_pins norns-snd-cs4271 cs4271 reset-gpios)" = "17 1" ]
}

@test "encoders and keys named for matron" {
  o=$(dtbo norns-buttons-encoders)
  for n in knob1 knob2 knob3 keys; do grep -q "$n {" <<<"$o"; done
  # by-path names: platform-soc:knobN-event and platform-keys-event
  for n in 1 2 3; do
    [ "$(fdtget "$(dtbo_path norns-buttons-encoders)" /__symbols__ "knob$n")" = "$(ov_path norns-buttons-encoders "knob$n")" ]
    ov_frag_target norns-buttons-encoders "knob$n" | grep -qx /soc
  done
  ov_frag_target norns-buttons-encoders keypad | grep -qx /
  [ "$(basename "$(ov_path norns-buttons-encoders keypad)")" = "keys" ]
}

@test "encoder pins are the shield's: E1 4/27, E2 12/25, E3 24/23" {
  expect=(_ "4 27" "12 25" "24 23")
  for n in 1 2 3; do
    [ "$(ov_get norns-buttons-encoders "knob$n" compatible)" = "rotary-encoder" ]
    # A then B, both active low
    [ "$(gpio_pins norns-buttons-encoders "knob$n" | tr '\n' ' ')" = "${expect[$n]%% *} 1 ${expect[$n]##* } 1 " ]
    # the pins' pinmux node: inputs with pull-ups
    [ "$(ov_get norns-buttons-encoders "knob_pins$n" brcm,pins)" = "${expect[$n]}" ]
    [ "$(ov_get norns-buttons-encoders "knob_pins$n" brcm,function)" = "0" ]
    [ "$(ov_get norns-buttons-encoders "knob_pins$n" brcm,pull)" = "2" ]
    [ "$(ov_get norns-buttons-encoders "knob$n" linux,axis)" = "0" ]
    ov_get norns-buttons-encoders "knob$n" rotary-encoder,relative-axis >/dev/null
    [ "$(ov_get norns-buttons-encoders "knob$n" rotary-encoder,steps-per-period)" = "2" ]
  done
}

@test "key pins are the shield's: K1 22, K2 26, K3 13" {
  [ "$(ov_get norns-buttons-encoders keypad compatible)" = "gpio-keys" ]
  expect=(_ 22 26 13)
  for n in 1 2 3; do
    # monome's codes: KEY_ESC, KEY_1, KEY_2 for K1..K3
    [ "$(ov_get norns-buttons-encoders "button$n" linux,code)" = "$n" ]
    [ "$(gpio_pins norns-buttons-encoders "button$n")" = "${expect[$n]} 1" ]
    [ "$(dirname "$(ov_path norns-buttons-encoders "button$n")")" = "$(ov_path norns-buttons-encoders keypad)" ]
  done
}

@test "pins stay overridable with monome's parameters" {
  f=$(dtbo_path norns-buttons-encoders)
  for p in e1_pin_a e1_pin_b e2_pin_a e2_pin_b e3_pin_a e3_pin_b b1_pin b2_pin b3_pin; do
    fdtget "$f" /__overrides__ "$p" >/dev/null
  done
}

@test "no display overlay and nothing on the OLED's GPIO5/6" {
  for f in "$REPO_ROOT"/overlays/*.dts; do
    ! grep -qi 'ssd1322\|fbtft' "$f"
  done
  for n in 1 2 3; do
    for p in $(ov_get norns-buttons-encoders "knob_pins$n" brcm,pins) $(gpio_pins norns-buttons-encoders "button$n" | cut -d' ' -f1); do
      [ "$p" != 5 ] && [ "$p" != 6 ]
    done
  done
}
