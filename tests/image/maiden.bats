#!/usr/bin/env bats
# maiden (monome/maiden built unchanged from its release tag, plus monome's
# released web app) and the default dust directory.

setup() {
  load ../helpers
  require_rootfs
}

M=/home/we/maiden
maiden_git() {
  in_ns git -c safe.directory='*' --no-optional-locks -C "$ROOTFS$M/src" "$@"
}

@test "maiden binary is aarch64 from the tag" {
  in_root file $M/maiden | grep -q 'ARM aarch64'
  in_root $M/maiden version | grep -q "$MAIDEN_TAG"
}
@test "maiden source is the untouched release" {
  [ "$(maiden_git rev-parse HEAD)" = "$MAIDEN_COMMIT" ]
  [ -z "$(maiden_git status --porcelain --untracked-files=no)" ]
}
@test "maiden web app present" {
  in_root test -f $M/app/build/index.html
}
@test "maiden data files installed and project set up" {
  in_root test -f $M/maiden.yaml
  in_root test -x $M/project-setup.sh
  in_root test -x $M/start.sh
  in_root test -f $M/dist/sources/base.json
  in_root test -f /home/we/dust/data/sources/base.json
  [ -z "$(in_root find $M /home/we/dust ! -user we)" ]
}
@test "no Go toolchain left" {
  ! in_root dpkg -s golang-go
  [ -z "$(in_root dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' 'golang-*' 2>/dev/null | awk '$1 ~ /^i/')" ]
  ! in_root test -e /home/we/go
  ! in_root test -e /root/go
  ! in_root test -e /root/.cache/go-build
  ! in_root test -e /home/we/.cache/go-build
}
@test "dust layout" {
  for d in code audio data; do
    [ "$(in_root stat -c %U /home/we/dust/$d)" = we ] || { echo "$d"; return 1; }
  done
  in_root test -d /home/we/dust/audio/common
  in_root test -f /home/we/dust/audio/common/606/606-HT.wav
}
@test "maiden socket on port 80" {
  grep -q 'ListenStream=80' "$ROOTFS/etc/systemd/system/norns-maiden.socket"
}
# norns.target requires norns-maiden.service: everything it starts must exist.
@test "maiden unit: binary, working directory and paths exist" {
  UNIT=$REPO_ROOT/config/norns-maiden.service
  exe=$(sed -n 's/^ExecStart=//p' "$UNIT" | cut -d' ' -f1)
  in_root file "$exe" | grep -q 'ARM aarch64'
  wd=$(sed -n 's/^WorkingDirectory=//p' "$UNIT")
  in_root test -d "$wd"
  for flag in app data doc; do
    p=$(sed -n "s/^ExecStart=.* --$flag \([^ ]*\).*/\1/p" "$UNIT")
    [ -n "$p" ] || { echo "no --$flag"; return 1; }
    case $p in /*) ;; *) p=$wd/$p ;; esac
    in_root test -d "$p" || { echo "--$flag $p"; return 1; }
  done
}
