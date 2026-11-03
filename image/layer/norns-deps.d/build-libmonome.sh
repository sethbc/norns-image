#!/bin/bash
# Build libmonome into /usr/local inside the root filesystem.
# usage: build-libmonome.sh <rootfs> <tag> <commit>
set -euo pipefail

root=$1
tag=$2
commit=$3
url=https://github.com/monome/libmonome

# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" /bin/bash -euo pipefail -c '
  src=$(mktemp -d /tmp/libmonome.XXXXXX)
  trap "rm -rf -- $src" EXIT
  git clone --quiet --depth 1 --branch "$1" "$2" "$src"
  [ "$(git -C "$src" rev-parse HEAD)" = "$3" ] || {
    echo "libmonome $1 is at $(git -C "$src" rev-parse HEAD), expected $3" >&2
    exit 1
  }
  cd "$src"
  python3 ./waf configure --prefix=/usr/local
  python3 ./waf
  python3 ./waf install
' _ "$tag" "$url" "$commit"

chroot "$root" ldconfig
