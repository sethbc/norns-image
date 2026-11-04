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

@test "prune_stale_out keeps only this build's image files" {
  O=$(mktemp -d)
  touch "$O"/n-abc.img.zst "$O"/n-abc.img.zst.sha256 "$O"/n-abc.sbom.zst "$O"/n-abc.manifest.zst \
        "$O"/n-old.img.zst "$O"/n-old.img.zst.sha256 "$O"/n-old.sbom.zst "$O"/n-old.manifest.zst \
        "$O"/n-abc-dirty.img.zst "$O"/rootfs-path "$O"/other.txt
  prune_stale_out "$O" n- n-abc
  [ "$(cd "$O" && LC_ALL=C ls | tr '\n' ' ')" = "n-abc.img.zst n-abc.img.zst.sha256 n-abc.manifest.zst n-abc.sbom.zst other.txt rootfs-path " ]
  rm -rf "$O"
}

@test "prune_stale_out is a no-op on an empty out dir" {
  O=$(mktemp -d)
  prune_stale_out "$O" n- n-abc
  [ -z "$(ls -A "$O")" ]
  rm -rf "$O"
}
