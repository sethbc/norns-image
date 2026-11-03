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
