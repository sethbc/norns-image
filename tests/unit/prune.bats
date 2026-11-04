load ../helpers

setup() {
  . "$REPO_ROOT/scripts/prune.sh"
  ns() { "$@"; }
  W=$(mktemp -d)
  mkdir -p "$W"/chroot-abc "$W"/deploy-abc "$W"/chroot-old "$W"/deploy-old "$W"/chroot-abc-dirty "$W"/other "$W"/image-n-abc "$W"/image-n-old
}

teardown() { rm -rf "$W"; }

@test "prune_stale_work keeps current version, removes other versions" {
  prune_stale_work "$W" abc n-abc
  [ -d "$W/chroot-abc" ]
  [ -d "$W/deploy-abc" ]
  [ -d "$W/image-n-abc" ]
  [ ! -e "$W/image-n-old" ]
  [ -d "$W/other" ]
  [ ! -e "$W/chroot-old" ]
  [ ! -e "$W/deploy-old" ]
  [ ! -e "$W/chroot-abc-dirty" ]
}

@test "prune_stale_work is a no-op on an empty work dir" {
  rm -rf "$W"/*
  prune_stale_work "$W" abc n-abc
}
