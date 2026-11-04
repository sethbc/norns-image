#!/usr/bin/env bats
# scripts/norns-cc-wrapper: lets the unchanged norns sources build on aarch64
# by dropping the 32-bit ARM float flags and -Werror its wscripts add.

load ../helpers

setup() {
  W=$(mktemp -d)
  FAKECC=$W/fakecc
  printf '#!/bin/sh\necho "$*"\n' > "$FAKECC"
  chmod +x "$FAKECC"
  WRAPPER=$REPO_ROOT/scripts/norns-cc-wrapper
}

teardown() { rm -rf "$W"; }

@test "drops 32-bit ARM float flags" {
  run "$WRAPPER" "$FAKECC" -O3 -mfpu=neon -mfloat-abi=hard -c x.c
  [ "$output" = "-O3 -c x.c" ]
}
@test "drops -Werror forms" {
  run "$WRAPPER" "$FAKECC" -Wall -Werror -Werror=format -Wextra
  [ "$output" = "-Wall -Wextra" ]
}
@test "keeps everything else in order" {
  run "$WRAPPER" "$FAKECC" -I a -DX=1 -o out x.c
  [ "$output" = "-I a -DX=1 -o out x.c" ]
}
@test "keeps arguments with spaces intact" {
  printf '#!/bin/sh\nprintf "[%%s]" "$@"\n' > "$FAKECC"
  run "$WRAPPER" "$FAKECC" -DNAME="a b" -mfpu=neon x.c
  [ "$output" = "[-DNAME=a b][x.c]" ]
}
@test "propagates compiler exit code" {
  run "$WRAPPER" false
  [ "$status" -eq 1 ]
}
# Installed as cc/gcc/c++/g++ symlinks, the link name picks /usr/bin/<name>.
@test "symlink name selects /usr/bin/<name>" {
  ln -s "$WRAPPER" "$W/echo"
  run "$W/echo" -O2 -mfpu=neon -Werror x.c
  [ "$status" -eq 0 ]
  [ "$output" = "-O2 x.c" ]
}
@test "no compiler given is a usage error" {
  run "$WRAPPER"
  [ "$status" -eq 2 ]
}
