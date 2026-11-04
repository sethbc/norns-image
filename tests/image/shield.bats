#!/usr/bin/env bats
# norns shield on the Pi 4: the codec modules (CS4270 from the
# monome-codecs DKMS package, CS4271 from the kernel), the overlays, and the
# boot configuration.

setup() {
  load ../helpers
  require_rootfs
}

FW=/boot/firmware
MODULES="snd-soc-cs4270 snd-soc-cs4271 snd-soc-cs4271-i2c"

kernels() { in_root ls /lib/modules; }

@test "two kernels to build for" {
  [ "$(kernels | wc -l)" -eq 2 ]
}

@test "codec modules built for every kernel" {
  for k in $(kernels); do
    for m in $MODULES; do
      in_root modinfo -k "$k" "$m" >/dev/null
    done
    # CS4270 is not in the Pi kernels: it is the DKMS build, which depmod
    # knows about
    in_root modinfo -k "$k" -F filename snd-soc-cs4270 | grep -q "^/lib/modules/$k/updates/dkms/snd-soc-cs4270.ko"
    in_root modinfo -k "$k" -F vermagic snd-soc-cs4270 | grep -q "^$k "
    in_root grep -q 'updates/dkms/snd-soc-cs4270.ko' "/lib/modules/$k/modules.dep"
    # matching the overlay's compatible
    in_root modinfo -k "$k" -F alias snd-soc-cs4270 | grep -q 'of:N\*T\*Ccirrus,cs4270'
  done
}

@test "dkms has the module installed for every kernel" {
  for k in $(kernels); do
    in_root dkms status -k "$k" monome-codecs/1.0 | grep -q ': installed'
  done
}

@test "dkms rebuilds on kernel upgrade" {
  in_root grep -qx 'AUTOINSTALL="yes"' /usr/src/monome-codecs-1.0/dkms.conf
  in_root dpkg -s linux-headers-rpi-v8 linux-headers-rpi-2712 dkms >/dev/null
  # dkms' kernel hook builds registered modules for a newly installed kernel
  in_root test -x /etc/kernel/postinst.d/dkms
}

@test "no module signing key baked into the image" {
  ! in_root sh -c 'ls /var/lib/dkms/mok.* 2>/dev/null' | grep -q . || false
}

@test "codec sources say where they come from" {
  in_root grep -q "raspberrypi/linux@$CODEC_SRC_COMMIT" /usr/src/monome-codecs-1.0/cs4270.c
  in_root grep -q 'GPL-2.0' /usr/src/monome-codecs-1.0/cs4270.c
}

@test "overlays installed" {
  for o in norns-snd-cs4270 norns-snd-cs4271 norns-buttons-encoders; do
    in_root test -s "$FW/overlays/$o.dtbo"
  done
}

@test "overlays apply to the image's Pi 4 device tree" {
  d=$BATS_TEST_TMPDIR
  in_ns cat "$ROOTFS$FW/bcm2711-rpi-4-b.dtb" > "$d/base.dtb"
  for o in norns-snd-cs4270 norns-snd-cs4271 norns-buttons-encoders; do
    in_ns cat "$ROOTFS$FW/overlays/$o.dtbo" > "$d/$o.dtbo"
  done
  for c in cs4270 cs4271; do
    fdtoverlay -i "$d/base.dtb" -o "$d/$c.dtb" "$d/norns-snd-$c.dtbo" "$d/norns-buttons-encoders.dtbo"
    [ "$(fdtget "$d/$c.dtb" /soc/sound simple-audio-card,name)" = "snd-rpi-monome" ]
    fdtget "$d/$c.dtb" "$(fdtget "$d/$c.dtb" /__symbols__ i2c1)/$c@$( [ $c = cs4270 ] && echo 48 || echo 10)" compatible | grep -qx "cirrus,$c"
  done
  for n in /soc/knob1 /soc/knob2 /soc/knob3; do
    [ "$(fdtget "$d/cs4270.dtb" "$n" compatible)" = "rotary-encoder" ]
  done
  [ "$(fdtget "$d/cs4270.dtb" /keys compatible)" = "gpio-keys" ]
}

@test "boot config" {
  require_image_stage
  c=$(in_root cat $FW/config.txt)
  for l in dtparam=spi=on dtparam=i2c_arm=on dtparam=i2s=on dtparam=audio=off dtoverlay=norns-buttons-encoders '# BEGIN norns-codec' '# END norns-codec'; do
    grep -qx "$l" <<<"$c"
  done
  ! grep -qx 'dtparam=audio=on' <<<"$c" || false
  # no display overlay: matron drives the OLED on spidev0.0 with GPIO5/6
  ! grep -v '^[[:space:]]*#' <<<"$c" | grep -qi 'ssd1322\|fbtft' || false
  # the codec block is empty until the detector (or the user) fills it, and
  # the norns lines apply to every board ([all])
  [ "$(sed -n '/^# BEGIN norns-codec$/,/^# END norns-codec$/p' <<<"$c" | wc -l)" -eq 2 ]
  [ "$(sed -n '/^dtoverlay=norns-buttons-encoders$/q; /^\[/p' <<<"$c" | tail -n1)" = "[all]" ]
  # rpi-image-gen's own settings are still there
  grep -qx 'auto_initramfs=1' <<<"$c"
}

@test "spidev buffer" {
  require_image_stage
  l=$(in_root cat $FW/cmdline.txt)
  grep -qw 'spidev.bufsiz=8192' <<<"$l"
  grep -qw 'rootwait' <<<"$l"
}

@test "codec detector enabled before jack" {
  [ "$(in_root systemctl is-enabled norns-codec-detect.service)" = enabled ]
  u=$ROOTFS/etc/systemd/system/norns-codec-detect.service
  grep -q 'Before=norns-jack.service' "$u"
  grep -q 'After=systemd-modules-load.service' "$u"
  grep -q 'SuccessExitStatus=2 10' "$u"
  [ -x "$ROOTFS/usr/local/sbin/norns-codec-detect" ]
  [ -x "$ROOTFS/usr/bin/pinctrl" ]
  [ -x "$ROOTFS/usr/sbin/i2cget" ]
  grep -qx i2c-dev "$ROOTFS/etc/modules-load.d/norns-i2c.conf"
}

# The detector's first-boot reboot must not cut short the other first-boot
# jobs: growing the root partition and filesystem, and generating the SSH
# host keys.
@test "codec detector runs after the first-boot jobs" {
  u=$ROOTFS/etc/systemd/system/norns-codec-detect.service
  after=" $(sed -n 's/^After=//p' "$u" | tr '\n' ' ') "
  for dep in norns-grow-root.service ssh-hostkeys-generate.service; do
    [[ "$after" == *" $dep "* ]] || { echo "not After=$dep"; return 1; }
    # the names are the image's real first-boot units
    [ "$(in_root systemctl is-enabled "$dep")" = enabled ] || { echo "$dep not enabled"; return 1; }
  done
}

@test "codec detector finds no shield in the build chroot and leaves config.txt alone" {
  require_image_stage
  c=$ROOTFS/boot/firmware/config.txt
  before=$(in_ns sha256sum "$c")
  # no I2C bus here: the probe fails, so the detector reports "no codec"
  run in_root env NORNS_CODEC_RESET_DELAY=0 NORNS_CODEC_SETTLE=0 NORNS_CODEC_BUS_WAIT=1 /usr/local/sbin/norns-codec-detect --reset /bin/true --probe /bin/false
  [ "$status" -eq 2 ]
  [ "$(in_ns sha256sum "$c")" = "$before" ]
}
