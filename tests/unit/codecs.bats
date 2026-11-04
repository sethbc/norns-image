#!/usr/bin/env bats
# packages/monome-codecs-dkms: the CS4270 driver vendored from
# raspberrypi/linux, built by DKMS.

setup() {
  load ../helpers
  P=$REPO_ROOT/packages/monome-codecs-dkms
}

@test "vendored source names the pinned raspberrypi/linux commit" {
  head -8 "$P/cs4270.c" | grep -q "raspberrypi/linux@$CODEC_SRC_COMMIT"
  head -8 "$P/cs4270.c" | grep -q 'sound/soc/codecs/cs4270.c'
  head -8 "$P/cs4270.c" | grep -q 'GPL-2.0'
}

@test "dkms.conf: monome-codecs 1.0, autoinstalled" {
  (
    . "$P/dkms.conf"
    [ "$PACKAGE_NAME" = monome-codecs ]
    [ "$PACKAGE_VERSION" = 1.0 ]
    [ "$AUTOINSTALL" = yes ]
    [ "${BUILT_MODULE_NAME[*]}" = snd-soc-cs4270 ]
  )
}

@test "Kbuild builds every module dkms.conf names" {
  grep -qx 'obj-m += snd-soc-cs4270.o' "$P/Makefile"
  grep -qx 'snd-soc-cs4270-y := cs4270.o' "$P/Makefile"
}
