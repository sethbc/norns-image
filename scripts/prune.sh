# shellcheck shell=bash
# Sourced by build.sh and tests. Needs an `ns` function (run a command in
# rpi-image-gen's user namespace) defined by the caller.

# prune_stale_work WORK VERSION IMAGE_NAME
# Remove chroot-*, deploy-* and image-* dirs under WORK that belong to other
# versions. They are owned by subordinate uids, hence ns.
prune_stale_work() {
  local work=$1 version=$2 name=$3 d
  for d in "$work"/chroot-* "$work"/deploy-* "$work"/image-*; do
    [ -d "$d" ] || continue
    case ${d##*/} in
      "chroot-$version"|"deploy-$version"|"image-$name") continue ;;
    esac
    echo "pruning stale $d"
    ns rm -rf -- "$d"
  done
}

# prune_stale_out OUT PREFIX IMAGE_NAME
# Remove PREFIX* files under OUT that are not IMAGE_NAME.*: the images,
# checksums, SBOMs and manifests of earlier builds, so OUT holds this build's
# files only. Other files (rootfs-path and friends) are left alone.
prune_stale_out() {
  local out=$1 prefix=$2 name=$3 f
  for f in "$out/$prefix"*; do
    [ -f "$f" ] || continue
    case ${f##*/} in
      "$name".*) continue ;;
    esac
    echo "pruning stale $f"
    rm -f -- "$f"
  done
}
