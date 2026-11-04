#!/usr/bin/env bats
# Vendored libraries: libgpiod v1 (matron's API; trixie only has v2) and libmonome.

setup() {
  load ../helpers
  require_rootfs
}

@test "libgpiod v1 visible to matron's build" {
  run in_root env PKG_CONFIG_PATH=/opt/norns/libgpiod1/lib/pkgconfig pkg-config --modversion libgpiod
  [ "$output" = "${LIBGPIOD1_TAG#v}" ]
}
# Only the prefix's own pkg-config path may expose v1, so a system (v2)
# libgpiod-dev installed later is never shadowed.
@test "libgpiod v1 does not leak into the default pkg-config path" {
  run in_root pkg-config --modversion libgpiod
  [[ "$output" != 1.* ]]
}
@test "libgpiod.so.2 on the loader path" {
  in_root ldconfig -p | grep -q 'libgpiod.so.2 .*/opt/norns/libgpiod1/lib'
}
@test "libmonome installed" {
  in_root ldconfig -p | grep -q libmonome.so
  [ -f "$ROOTFS/usr/local/include/monome.h" ]
}
@test "build checkouts are not left in the image" {
  [ -z "$(ls -A "$ROOTFS/tmp")" ]
}
# liblo 0.31 is norns' private copy: same soname as trixie's 0.32, so it must
# stay off the default pkg-config and loader paths.
@test "liblo 0.31 visible through its own pkg-config path only" {
  run in_root env PKG_CONFIG_PATH=/opt/norns/liblo031/lib/pkgconfig pkg-config --modversion liblo
  [ "$output" = "$LIBLO031_TAG" ]
  run in_root pkg-config --modversion liblo
  [ "$output" != "$LIBLO031_TAG" ]
}
@test "liblo 0.31 is not on the loader path" {
  ! in_root ldconfig -p | grep -q /opt/norns/liblo031
  ! in_root grep -rqs /opt/norns/liblo031 /etc/ld.so.conf /etc/ld.so.conf.d
}
# libmonome's OSC support is the protocol_osc module it dlopens.
@test "libmonome loads the private liblo 0.31" {
  in_root ldd /usr/local/lib/monome/protocol_osc.so | grep -q 'liblo.so.7 => /opt/norns/liblo031/lib/liblo.so.7'
}
