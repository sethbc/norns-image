#!/bin/bash
# Build maiden from its release tag, unchanged, into /home/we/maiden, add
# monome's released web app, and create the default dust directory.
# usage: install-maiden.sh <rootfs> <maiden-tag> <maiden-commit> \
#          <update-url> <update-sha256> <update-version> \
#          <dust-audio-url> <dust-audio-sha256>
#
# Layout (the same one maiden's tool/release.sh makes, which the unit
# norns-maiden.service and the Go server expect):
#   ~/maiden/maiden            Go binary, built with the ldflags of maiden's
#                              Makefile (cmd.version from `git describe`,
#                              cmd.compileTime; here the commit date, so the
#                              build doesn't depend on the clock)
#   ~/maiden/src               the pinned clone, kept so its state is checkable
#   ~/maiden/{maiden.yaml,start.sh,project-setup.sh,dist/sources}
#                              from the clone, as release.sh copies them
#   ~/maiden/app/build         monome's released web build, from the update
#                              tarball: the app is react-scripts 1.0.17, which
#                              doesn't build with trixie's Node, and its output
#                              is architecture-independent
#   ~/dust/{code,audio,data}   default dust; audio/common from monome's release
# The sources stay byte-identical to the tag. Only the build is adapted:
# CGO_ENABLED=0 (maiden has no C code), a throw-away GOPATH/GOCACHE (nothing
# of Go is left behind) and GOTOOLCHAIN=local (use only the packaged Go).
# golang-go comes from the layer's package list and is purged here.
set -euo pipefail

root=$1
tag=$2
commit=$3
update_url=$4
update_sha256=$5
update_version=$6
dust_url=$7
dust_sha256=$8
url=https://github.com/monome/maiden

# Everything as we, so everything under ~ is we's. $1.. are in the order
# above, without the root.
# shellcheck disable=SC2016  # expanded by the shell inside the chroot
chroot "$root" setpriv --reuid=we --regid=we --init-groups \
  env -i HOME=/home/we USER=we LOGNAME=we LANG=C.UTF-8 PATH=/usr/local/bin:/usr/bin:/bin \
  /bin/bash -euo pipefail -c '
  tag=$1 url=$2 commit=$3 update_url=$4 update_sha256=$5 update_version=$6
  dust_url=$7 dust_sha256=$8
  work=$(mktemp -d /tmp/maiden.XXXXXX)
  # Go makes its module cache read-only.
  trap "chmod -R u+w -- $work; rm -rf -- $work" EXIT

  m=/home/we/maiden
  mkdir -p "$m"
  git clone --quiet --depth 1 --branch "$tag" "$url" "$m/src"
  [ "$(git -C "$m/src" rev-parse HEAD)" = "$commit" ] || {
    echo "maiden $tag is at $(git -C "$m/src" rev-parse HEAD), expected $commit" >&2
    exit 1
  }

  cd "$m/src"
  ldflags="-X github.com/monome/maiden/cmd.version=$(git describe --tags)"
  ldflags+=" -X github.com/monome/maiden/cmd.compileTime=$(date -u -d "@$(git log -1 --format=%ct)" +%Y-%m-%dT%H:%M)"
  GOPATH=$work/gopath GOCACHE=$work/gocache GOTOOLCHAIN=local CGO_ENABLED=0 \
    go build -ldflags="$ldflags" -o "$m/maiden"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || {
    echo "building changed the maiden sources" >&2
    exit 1
  }

  # what tool/release.sh puts next to the binary
  cp tool/start.sh tool/project-setup.sh maiden.yaml "$m/"
  mkdir -p "$m/dist/sources"
  cp sources/*.json "$m/dist/sources/"

  # the released web app
  curl -fsSL --retry 3 -o "$work/update.tgz" "$update_url"
  echo "$update_sha256  $work/update.tgz" | sha256sum -c --quiet
  tar -xzf "$work/update.tgz" -C "$m" --strip-components=2 "$update_version/maiden/app/build"
  [ -f "$m/app/build/index.html" ]

  # dust
  mkdir -p /home/we/dust/code /home/we/dust/audio /home/we/dust/data
  curl -fsSL --retry 3 -o "$work/dust.tgz" "$dust_url"
  echo "$dust_sha256  $work/dust.tgz" | sha256sum -c --quiet
  tar -xzf "$work/dust.tgz" -C /home/we/dust/audio
  [ -d /home/we/dust/audio/common ]

  # sources and catalogs for maiden (its project-setup.sh)
  cd "$m"
  ./project-setup.sh >/dev/null
' _ "$tag" "$url" "$commit" "$update_url" "$update_sha256" "$update_version" "$dust_url" "$dust_sha256"

# No Go toolchain stays in the image.
go_pkgs=$(chroot "$root" dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 'golang-*' 2>/dev/null \
  | awk '$1 ~ /^i/ {print $2}' || true)
if [ -n "$go_pkgs" ]; then
  # shellcheck disable=SC2086  # one word per package
  chroot "$root" apt-get -y purge --autoremove $go_pkgs
fi
rm -rf "$root/root/go" "$root/root/.cache/go-build" "$root/home/we/go" "$root/home/we/.cache/go-build"
