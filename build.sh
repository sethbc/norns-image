#!/bin/bash
# Build the norns trixie arm64 image with rpi-image-gen.
#
# usage: ./build.sh [--fs-only] [--clean]
#   --fs-only  build the root filesystem only (no disk image)
#   --clean    remove work/ and out/ first
#
# Writes to out/:
#   norns-trixie-arm64-<version>.img.zst (+ .sha256, .sbom.zst, .manifest.zst)
#   rootfs-path        absolute path of the built filesystem
#   rootfs-used-bytes  space the root filesystem uses (max 2000000000)
set -euo pipefail

TOP=$(cd "$(dirname "$0")" && pwd)
IG=$TOP/vendor/rpi-image-gen
WORK=$TOP/work
OUT=$TOP/out
MAX_ROOTFS_BYTES=2000000000

die() { echo "build.sh: $*" >&2; exit 1; }
# Run a command in rpi-image-gen's user namespace, where the build output's
# subordinate uids map back to the uids the image will have.
ns() { NS_SETUP='_ns_setup() { :; }' "$IG/bin/ns" "$@"; }
usage() { sed -n '4,6s/^# \{0,1\}//p' "$0"; }

fs_only=0
clean=0
for arg in "$@"; do
  case $arg in
    --fs-only) fs_only=1 ;;
    --clean)   clean=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; exit 2 ;;
  esac
done

[ -x "$IG/rpi-image-gen" ] || die "vendor/rpi-image-gen is missing; run: git submodule update --init"

set -a
. "$TOP/versions.env"
set +a

ig_commit=$(git -C "$IG" rev-parse HEAD)
[ "$ig_commit" = "$RPI_IMAGE_GEN_COMMIT" ] \
  || die "vendor/rpi-image-gen is at $ig_commit, versions.env pins $RPI_IMAGE_GEN_COMMIT"

if [ "$clean" = 1 ]; then
  [ -e "$WORK" ] && ns rm -rf -- "$WORK"
  rm -rf -- "$OUT"
fi

version=$(git -C "$TOP" describe --tags --always --dirty)
name=norns-trixie-arm64-$version

# Every versions.env entry reaches the layers as IGconf_norns_<lowercase name>.
overrides=(IGconf_artefact_version="$version" IGconf_image_name="$name")
while IFS='=' read -r key _; do
  overrides+=("IGconf_norns_${key,,}=${!key}")
done < <(grep -E '^[A-Z][A-Z0-9_]*=' "$TOP/versions.env")

mkdir -p "$WORK" "$OUT"
# Tests read rootfs-path; never let a failed build leave a stale one behind.
rm -f -- "$OUT/rootfs-path" "$OUT/rootfs-used-bytes"
ig_args=(build -S "$TOP/image" -c norns.yaml -B "$WORK")
[ "$fs_only" = 1 ] && ig_args+=(-f)

start=$SECONDS
"$IG/rpi-image-gen" "${ig_args[@]}" -- "${overrides[@]}"

rootfs=$WORK/chroot-$version/filesystem
[ -d "$rootfs/etc" ] || die "no filesystem at $rootfs"
echo "$rootfs" > "$OUT/rootfs-path"

# /boot/firmware is its own partition, so it doesn't count against root.
used=$(ns sh -c 'cd "$1" && du -s -x -B1 --exclude=./boot/firmware .' _ "$rootfs" | cut -f1)
echo "$used" > "$OUT/rootfs-used-bytes"
echo "rootfs used bytes: $used (limit $MAX_ROOTFS_BYTES)"
[ "$used" -le "$MAX_ROOTFS_BYTES" ] || die "root filesystem uses $used bytes, over the $MAX_ROOTFS_BYTES limit"

if [ "$fs_only" = 0 ]; then
  deploy=$WORK/deploy-$version
  cp "$deploy/$name.img.zst" "$OUT/"
  cp "$deploy/filesystem-$version.sbom.zst" "$OUT/$name.sbom.zst"
  cp "$deploy/manifest.zst" "$OUT/$name.manifest.zst"
  (cd "$OUT" && sha256sum "$name.img.zst" > "$name.img.zst.sha256")
  echo "image: $OUT/$name.img.zst"
fi

echo "build time: $((SECONDS - start))s"
