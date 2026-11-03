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
