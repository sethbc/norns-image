# norns trixie image — Phase 0–1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A scripted, CI-built Raspberry Pi OS trixie arm64 image that boots unchanged norns v2.9.4 on a Pi 4 + shieldXL (screen, keys, encoders, audio, maiden), and already contains both Pi 4 and Pi 5 kernels.

**Architecture:** `rpi-image-gen` (git submodule, pinned) builds the image from our own config and layers under `image/`. Layers add, in order: base system and users, modernized OS config, vendored libraries (libgpiod v1, libmonome), the norns runtime built from pinned release tags through a compiler-flag wrapper, maiden, and Pi 4 shield hardware support (device-tree overlays, DKMS-built codec modules, a boot-time codec detector). bats tests check host-side scripts (unit) and the built root filesystem (image); Seth runs the on-device acceptance checklist.

**Tech Stack:** rpi-image-gen (mmdebstrap, YAML layers), bash, bats-core, device-tree (`dtc`), DKMS, waf/cmake (norns), Go (maiden), GitHub Actions (`ubuntu-24.04-arm`).

**Spec:** `docs/superpowers/specs/2026-11-03-trixie-image-design.md`

Later plans (not here): phase 2 Pi 5 overlays, phase 3 shieldXL MIDI, phase 4 CM3, phase 5 PiSugar.

## Global Constraints

- Fork only: branches/PRs/releases on `sethbc/norns-image`. `gh pr create --repo sethbc/norns-image --base main`. Never push to the `upstream` remote.
- Work on `amd64-mini` in `~/src/norns-image`; other clones go in `~/src`. Push from wherever GitHub credentials exist (currently Seth's Mac) — the Linux box has no git identity; commit there with `git -c user.name="Seth Chandler" -c user.email=sethbc@sethbc.org`, or ask Seth to configure it.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. PR bodies end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- monome software is built from release tags **unchanged**: `git status --porcelain --untracked-files=no` must be empty in every monome checkout in the image.
- Copy nothing from `The-XOR/norns-image`.
- Pinned versions (put in `versions.env`):
  - `NORNS_TAG=v2.9.4` `NORNS_COMMIT=14bbeae8646c6717f6bb44c8cd60250bf94b6042` `NORNS_VERSION_TXT=260102`
  - `NORNS_UPDATE_URL=https://github.com/monome/norns/releases/download/v2.9.4/norns260102.tgz` (sha256 from `norns260102.sha256` in the same release)
  - `MAIDEN_TAG=v1.1.6` `MAIDEN_COMMIT=905413da55d74f6f9fa83bcdb91cdb40eee7701f`
  - `LIBMONOME_TAG=v1.4.11` `LIBMONOME_COMMIT=9055ea22fd824839be821c10f6e9b13e9d2aa3cd`
  - `LIBGPIOD1_TAG=v1.6.5` `LIBGPIOD1_COMMIT=44e6985fa2afeca880607ec9238ece110164b774` (git.kernel.org libgpiod)
  - `CODEC_SRC_COMMIT=a4985478de14b3a83c8e04fed68377c1bdae735d` (raspberrypi/linux rpi-6.18.y, source of vendored codec files)
  - `DUST_AUDIO_COMMON_URL=https://github.com/monome/norns/releases/download/v2.7.1/dust-audio-common.tgz` + its sha256
  - rpi-image-gen: submodule at `ff5fb451fac47debf441a5a2b39aa3ade7988bd6`
- Every download is checksum-verified; a mismatch fails the build.
- User `we`, password `sleep` (passwordless sudo), hostname `norns`, SSH enabled.
- Root filesystem used space ≤ **2.0 GB** or the build fails.
- Boot files live in `/boot/firmware`; `cmdline.txt` contains `spidev.bufsiz=8192`.
- ALSA card name `snd-rpi-monome` (JACK opens `hw:sndrpimonome`).
- matron's input paths must exist on device: `/dev/input/by-path/platform-keys-event`, `/dev/input/by-path/platform-soc:knob{1,2,3}-event`.
- Shield pins: E1 4/27, E2 12/25, E3 24/23, K1 22, K2 26, K3 13; OLED on spidev0.0 with D/C GPIO5, reset GPIO6 on `gpiochip0`; codec reset GPIO17; CS4270 at i2c-1 `0x48`, CS4271 at i2c-1 `0x10`.

## Review Focus

1. **Kernel upgraded on the device** (`apt upgrade` pulls a new `linux-image-rpi-*`) → codec modules must rebuild; audio keeps working after reboot. *(Task 7: dkms autoinstall + headers metapackages test.)*
2. **No shield, or an unknown codec** → the detector must not reboot-loop and must not delete a working overlay line. *(Task 8: "nothing found" and idempotence tests.)*
3. **User taps SYSTEM > UPDATE** (stable or K1-alt beta) → nothing in `~/norns` or `~/maiden` changes. *(Task 5: update guard test.)*
4. **First boot on a larger SD card** → root partition grows to fill it (today's images need a manual expand). *(Task 1: rootfs test for the expand mechanism; acceptance checklist.)*
5. **The phase-1 image is flashed onto a Pi 5** → it boots to a shell (even before Pi 5 shield support) and does not brick. *(Task 1: both kernels present; acceptance checklist "Pi 5 smoke".)*

---

## File Structure

```
.gitmodules                         vendor/rpi-image-gen submodule
vendor/rpi-image-gen/               pinned rpi-image-gen
versions.env                        all pinned upstream versions + checksums
build.sh                            single entry point (local + CI)
image/                              rpi-image-gen source dir (-S)
  config/norns.yaml                 top-level config
  device/norns-pi45/device.yaml     device layer: generic64 + 2712 kernel + headers
  layer/norns-base.yaml             users, hostname, ssh, base packages, trims
  layer/norns-os.yaml               modernized OS config (from config/)
  layer/norns-deps.yaml             libgpiod v1, libmonome from source
  layer/norns-runtime.yaml          norns build, SC classes, units, update guard
  layer/norns-maiden.yaml           maiden binary + web app, dust
  layer/norns-shield.yaml           overlays, codec DKMS, config.txt, detector
  layer/<name>.d/                   assets/hooks for each layer
overlays/                           .dts sources (phase 1: Pi 4 variants)
packages/monome-codecs-dkms/        vendored cs4270/cs4271 sources + dkms.conf
scripts/norns-cc-wrapper            drops -mfpu=*, -mfloat-abi=*, -Werror*
scripts/norns-codec-detect          probes codec, manages config.txt block
config/                             existing units/config, modernized in place
tests/helpers.bash                  ROOTFS discovery, in_root helper
tests/run.sh                        `tests/run.sh unit|image|all`
tests/unit/*.bats                   host-side script tests
tests/image/*.bats                  built-rootfs tests
.github/workflows/build.yml         CI build + release
docs/testing/acceptance.md          on-device checklist (Seth)
```
Removed at the end of Task 3: `setup.sh`, `build-dev-image.md` (replaced by a "Building" section in `README.md`).

---

### Task 1: Skeleton build with both kernels

**Files:**
- Create: `.gitmodules`, `vendor/rpi-image-gen` (submodule), `versions.env`, `build.sh`, `image/config/norns.yaml`, `image/device/norns-pi45/device.yaml`, `image/layer/norns-base.yaml`, `tests/helpers.bash`, `tests/run.sh`, `tests/image/base.bats`
- Modify: `.gitignore` (add `work/`, `out/`)

**Interfaces:**
- Produces:
  - `./build.sh [--fs-only] [--clean]` → exit 0 on success; writes `out/norns-trixie-arm64-<git describe>.img.zst`, `.sha256`, SBOM, manifest (not with `--fs-only`), plus `out/rootfs-path` (absolute path to the built chroot filesystem) and `out/rootfs-used-bytes`. Fails if used bytes > 2000000000.
  - `build.sh` sources `versions.env` and passes each value to rpi-image-gen as `IGconf_norns_<lowercase name>=<value>` overrides; layers read them as `${IGconf_norns_norns_tag}` etc.
  - Layers declare `X-Env-VarPrefix: norns` and an `assetdir: ${DIRECTORY}` variable (pattern from `device/pi4/device.yaml`) so hooks reach `image/layer/<name>.d/`.
  - `tests/helpers.bash`: `ROOTFS` (from `out/rootfs-path`), `in_root <cmd...>` (= `sudo chroot "$ROOTFS" <cmd...>`, works via qemu binfmt), `rootfs_file <path>`.
  - `tests/run.sh unit|image|all` runs `bats tests/unit`, `bats tests/image`, or both.
- Device layer `norns-pi45`: Requires `rpi-generic64` (v8 kernel, all-device firmware); also installs `linux-image-rpi-2712`, `linux-headers-rpi-v8`, `linux-headers-rpi-2712`. Provides `rpi-device`. (Can't require `rpi-linux-2712` — it requires `hw:soc:bcm2712`.)
- `norns-base`: user1 `we` via `device_user1passhash` (generate once with `openssl passwd -6 -salt nornsimage sleep`, commit the hash), `device_user1sudo=nopasswd`, hostname `norns`, `openssh-server` enabled, packages `git i2c-tools vim-tiny`.

- [ ] **Step 1: Write `tests/image/base.bats`**

```bash
@test "user we exists with uid 1000 and the sleep password" {
  run in_root getent passwd we;  [[ "$output" == we:x:1000:1000:* ]]
  hash=$(in_root getent shadow we | cut -d: -f2)
  [ "$(openssl passwd -6 -salt "$(cut -d'$' -f3 <<<"$hash")" sleep)" = "$hash" ]
}
@test "we has passwordless sudo"        { run in_root sudo -l -U we; [[ "$output" == *"NOPASSWD: ALL"* ]]; }
@test "hostname is norns"               { [ "$(cat "$ROOTFS/etc/hostname")" = norns ]; }
@test "ssh is enabled"                  { run in_root systemctl is-enabled ssh; [ "$output" = enabled ]; }
@test "Pi 4 and Pi 5 kernels installed" { [ -f "$ROOTFS/boot/firmware/kernel8.img" ] && [ -f "$ROOTFS/boot/firmware/kernel_2712.img" ]; }
@test "headers for both kernel flavours" { run in_root dpkg -s linux-headers-rpi-v8 linux-headers-rpi-2712; [ "$status" -eq 0 ]; }
@test "root grows on first boot"        { skip_unless_expand_known; }   # see Step 3
@test "trixie arm64"                    { grep -q 'VERSION_CODENAME=trixie' "$ROOTFS/etc/os-release"; [ "$(in_root dpkg --print-architecture)" = arm64 ]; }
```

- [ ] **Step 2: Run `./build.sh --fs-only && tests/run.sh image` — expect FAIL (no build.sh yet)**

- [ ] **Step 3: Implement the files listed above.** Find which mechanism `image-rpios` uses to grow the root partition on first boot (look in `vendor/rpi-image-gen/image/` and `layer/rpi/`); replace `skip_unless_expand_known` with an assertion that it is installed/enabled. If none exists, add `rpi-resize` equivalent via a `systemd-repart` / `x-systemd.growfs` fstab option and assert that.

- [ ] **Step 4: Run `./build.sh && tests/run.sh image` — expect PASS, image in `out/`, used bytes printed and < 2.0 GB**

- [ ] **Step 5: Commit** — `git add -A && git commit -m "build: rpi-image-gen skeleton with Pi 4 + Pi 5 kernels"`

---

### Task 2: CI build and release

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `./build.sh`, `tests/run.sh`.
- Produces: on `pull_request` and `push` to `main`: build + `tests/run.sh all`, upload `out/*` as an artifact. On tag `v*`: same, then `gh release create` on `sethbc/norns-image` with `out/*.img.zst`, `.sha256`, SBOM, manifest.
- Runner `ubuntu-24.04-arm`; checkout with `submodules: true`; install deps with `vendor/rpi-image-gen/install_deps.sh` + `bats`.

- [ ] **Step 1: Write the workflow; validate with `actionlint .github/workflows/build.yml` (install via `go install github.com/rhysd/actionlint/cmd/actionlint@latest` or the release binary) — expect no errors**
- [ ] **Step 2: Push the branch to `origin` (sethbc) and open a draft PR to `sethbc/norns-image` main; expect the `build` job green and an artifact containing `.img.zst`**
- [ ] **Step 3: Commit** — `ci: build image on arm64 runners and publish releases`

---

### Task 3: Modernized OS configuration layer

**Files:**
- Create: `image/layer/norns-os.yaml`, `image/layer/norns-os.d/` (hooks), `config/polkit/55-maiden-systemctl.rules`, `tests/image/os.bats`
- Modify: `config/*` as needed for trixie; `README.md` (add "Building" section: `git clone --recursive`, `./build.sh`, where output lands, how to flash)
- Delete: `config/55-maiden-systemctl.pkla`, `config/rsyslog`, `config/rsyslog.conf`, `setup.sh`, `build-dev-image.md`

**Interfaces:**
- Produces in rootfs: everything `setup.sh` installed except the norns units (Task 5) — systemd env drop-in, `/etc/profile.d/10-default-env-vars.sh`, `~we/.bashrc`, motd, samba config + `smbpasswd` for `we`/`sleep`, `/etc/modprobe.d/blacklist-8192cu.conf`, `/etc/network/interfaces`, NetworkManager conf.d files, `journald.conf`, `logrotate.conf`, `/etc/security/limits.d/99-realtime.conf`; masks `apt-daily.timer`, `apt-daily-upgrade.timer`, `alsa-restore.service`, `alsa-state.service`; packages `network-manager dnsmasq-base samba avahi-daemon midisport-firmware`. Not installed: rsyslog, dphys-swapfile, exim4, nfs-common, triggerhappy, plymouth, modemmanager.
- polkit rule: allow `unix-user:we` the action `org.freedesktop.systemd1.manage-units`.
- USB auto-mount (`usbmount` replacement in the spec) is **dropped**: norns v2.9.4's SYSTEM menu has no SYNC page (`lua/core/menu/system.lua`: DEVICES, WIFI, MODS, SETTINGS, RESTART, UPDATE), so nothing in norns needs it. Say so in README under "Differences from monome's images".

- [ ] **Step 1: Write `tests/image/os.bats`** — one test per item above, e.g.:

```bash
@test "polkit lets we manage units" { grep -q 'org.freedesktop.systemd1.manage-units' "$ROOTFS/etc/polkit-1/rules.d/55-maiden-systemctl.rules"; grep -q '"we"' "$ROOTFS/etc/polkit-1/rules.d/55-maiden-systemctl.rules"; }
@test "no legacy pkla"              { [ ! -e "$ROOTFS/etc/polkit-1/localauthority/50-local.d/55-maiden-systemctl.pkla" ]; }
@test "apt timers masked"           { run in_root systemctl is-enabled apt-daily.timer; [ "$output" = masked ]; }
@test "no rsyslog or swap"          { ! in_root dpkg -s rsyslog && ! in_root dpkg -s dphys-swapfile; }
@test "samba user we exists"        { in_root pdbedit -L | grep -q '^we:'; }
@test "JACK env defaults"           { grep -q 'JACK_NO_START_SERVER=1' "$ROOTFS/etc/systemd/system.conf.d/10-default-env-vars.conf"; }
```
- [ ] **Step 2: `./build.sh --fs-only && tests/run.sh image` — expect os.bats FAIL**
- [ ] **Step 3: Implement the layer, add it to `norns.yaml`, convert pkla → rules, delete the retired files, update README**
- [ ] **Step 4: `./build.sh --fs-only && tests/run.sh image` — expect PASS**
- [ ] **Step 5: Commit** — `image: modernized OS config layer; retire setup.sh`

---

### Task 4: Vendored libraries — libgpiod v1 and libmonome

**Files:**
- Create: `image/layer/norns-deps.yaml`, `image/layer/norns-deps.d/build-libgpiod1.sh`, `image/layer/norns-deps.d/build-libmonome.sh`, `tests/image/deps.bats`

**Interfaces:**
- Produces:
  - libgpiod `v1.6.5` installed to prefix `/opt/norns/libgpiod1`; `/opt/norns/libgpiod1/lib/pkgconfig/libgpiod.pc`; `/etc/ld.so.conf.d/norns-libgpiod1.conf` containing `/opt/norns/libgpiod1/lib`. Its soname is `libgpiod.so.2`; trixie's libgpiod 2.x (`libgpiod.so.3`) remains installed.
  - libmonome `v1.4.11` installed to `/usr/local` (waf `configure --prefix=/usr/local`), `ldconfig` run.
  - Build tools/headers kept in the image (DKMS needs gcc anyway): `build-essential pkg-config autoconf automake libtool autoconf-archive python3 cmake libudev-dev liblo-dev`.
- Each build script: shallow-clone at the pinned tag, `git rev-parse HEAD` must equal the pinned commit or exit 1.

- [ ] **Step 1: Write `tests/image/deps.bats`**

```bash
@test "libgpiod v1 visible to matron's build" { run in_root env PKG_CONFIG_PATH=/opt/norns/libgpiod1/lib/pkgconfig pkg-config --modversion libgpiod; [ "$output" = 1.6.5 ]; }
@test "system libgpiod stays v2"             { run in_root pkg-config --modversion libgpiod; [[ "$output" == 2.* ]]; }
@test "libgpiod.so.2 on the loader path"     { in_root ldconfig -p | grep -q 'libgpiod.so.2 .*/opt/norns/libgpiod1/lib'; }
@test "libmonome installed"                  { in_root ldconfig -p | grep -q libmonome.so; [ -f "$ROOTFS/usr/local/include/monome.h" ]; }
```
- [ ] **Step 2: Build fs, run — expect FAIL**
- [ ] **Step 3: Implement the layer and scripts; add to `norns.yaml` before the runtime layer**
- [ ] **Step 4: Build fs, run — expect PASS**
- [ ] **Step 5: Commit** — `image: vendored libgpiod v1 and libmonome`

---

### Task 5: norns runtime from the unchanged release

**Files:**
- Create: `scripts/norns-cc-wrapper`, `tests/unit/cc-wrapper.bats`, `image/layer/norns-runtime.yaml`, `image/layer/norns-runtime.d/build-norns.sh`, `tests/image/runtime.bats`
- Modify: `config/norns-*.service`, `config/norns.target` (paths checked against trixie: `/usr/bin/sclang`, `/usr/bin/jack_wait`, `/usr/bin/jackd`)

**Interfaces:**
- Consumes: Task 4 libs.
- Produces:
  - `norns-cc-wrapper <real-compiler> [args...]`: execs `<real-compiler>` with every argument except those matching `-mfpu=*`, `-mfloat-abi=*`, `-Werror`, `-Werror=*`; order of remaining args preserved; exit status is the compiler's. Installed in the image at `/usr/local/lib/norns-build/` with symlinks `cc`, `gcc`, `c++`, `g++` that call it with `/usr/bin/<name>`; that dir is put first on `PATH` **only** for the norns build (also `CC`/`CXX` exported for waf and cmake).
  - `/home/we/norns`: git checkout of `NORNS_TAG`, `HEAD` = `NORNS_COMMIT`, submodules initialised, owned by `we`; built with `./waf configure` (no `--release`) with `PKG_CONFIG_PATH=/opt/norns/libgpiod1/lib/pkgconfig` then `./waf build`.
  - SC: `supercollider-language supercollider-server sc3-plugins` from trixie; `/home/we/.local/share/SuperCollider/Extensions` created; `norns/sc/install.sh` run as `we`.
  - Units from `config/` installed to `/etc/systemd/system`; `norns.target` enabled.
  - Update guard: `/home/we/version.txt` = `NORNS_VERSION_TXT` (so the menu reports "up to date" for stable); `/home/we/update` is an empty root-owned directory with the immutable attribute (`chattr +i`) so a K1-alt/beta install can't download or unpack anything.

- [ ] **Step 1: Write `tests/unit/cc-wrapper.bats`** (`setup` writes `$FAKECC`, a script that prints `"$*"`)

```bash
@test "drops 32-bit ARM float flags"  { run scripts/norns-cc-wrapper "$FAKECC" -O3 -mfpu=neon -mfloat-abi=hard -c x.c; [ "$output" = "-O3 -c x.c" ]; }
@test "drops -Werror forms"           { run scripts/norns-cc-wrapper "$FAKECC" -Wall -Werror -Werror=format -Wextra; [ "$output" = "-Wall -Wextra" ]; }
@test "keeps everything else in order" { run scripts/norns-cc-wrapper "$FAKECC" -I a -DX=1 -o out x.c; [ "$output" = "-I a -DX=1 -o out x.c" ]; }
@test "propagates compiler exit code" { run scripts/norns-cc-wrapper false; [ "$status" -eq 1 ]; }
```
- [ ] **Step 2: `tests/run.sh unit` — expect FAIL**
- [ ] **Step 3: Implement `scripts/norns-cc-wrapper` (bash, `exec`)**
- [ ] **Step 4: `tests/run.sh unit` — expect PASS; commit** — `build: compiler wrapper for unchanged norns on arm64`
- [ ] **Step 5: Write `tests/image/runtime.bats`**

```bash
@test "norns source is the untouched release" { [ "$(in_root git -C /home/we/norns rev-parse HEAD)" = "$NORNS_COMMIT" ]; [ -z "$(in_root git -C /home/we/norns status --porcelain --untracked-files=no)" ]; }
@test "norns binaries are aarch64" { for b in matron/matron crone/crone ws-wrapper/ws-wrapper watcher/watcher maiden-repl/maiden-repl; do file "$ROOTFS/home/we/norns/build/$b" | grep -q 'ARM aarch64'; done; }
@test "matron links libgpiod v1"   { in_root ldd /home/we/norns/build/matron/matron | grep -q '/opt/norns/libgpiod1/lib/libgpiod.so.2'; ! in_root ldd /home/we/norns/build/matron/matron | grep -q 'not found'; }
@test "norns SC classes installed" { [ -e "$ROOTFS/home/we/.local/share/SuperCollider/Extensions/norns-config.sc" ]; }
@test "norns.target enabled"       { run in_root systemctl is-enabled norns.target; [ "$output" = enabled ]; }
@test "update menu is inert"       { [ "$(cat "$ROOTFS/home/we/version.txt")" = "$NORNS_VERSION_TXT" ]; sudo lsattr -d "$ROOTFS/home/we/update" | grep -q -- '-i-'; [ -z "$(ls -A "$ROOTFS/home/we/update")" ]; }
@test "home owned by we"           { [ "$(stat -c %U "$ROOTFS/home/we/norns")" = we ]; }
```
- [ ] **Step 6: Build fs, run — expect FAIL**
- [ ] **Step 7: Implement the layer and `build-norns.sh`; verify by reading `lua/core/menu/update.lua` at the tag that the immutable `~/update` leaves the menu in a sane state (download fails → returns to menu) and note the observed behaviour in the script header comment**
- [ ] **Step 8: Build fs, run — expect PASS**
- [ ] **Step 9: Commit** — `image: build unchanged norns v2.9.4 with SC classes and units`

---

### Task 6: maiden and dust

**Files:**
- Create: `image/layer/norns-maiden.yaml`, `image/layer/norns-maiden.d/install-maiden.sh`, `tests/image/maiden.bats`

**Interfaces:**
- Produces:
  - `/home/we/maiden/maiden`: Go binary built from `MAIDEN_TAG` (`HEAD` = `MAIDEN_COMMIT`, tree clean) with the ldflags from maiden's `Makefile`; `golang-go` installed for the build and purged afterwards.
  - `/home/we/maiden/app/build`: copied from the release update tarball `NORNS_UPDATE_URL` (sha256-verified), path `<version>/maiden/app/build` inside it (confirm the path; maiden's web app uses react-scripts 1.0.17, which won't build on trixie's Node, so we use monome's released, architecture-independent web build). Also copy `maiden.yaml`, `project-setup.sh`, `start.sh` and `dist/sources/` from the same place if present; run `project-setup.sh` as `we`.
  - `/home/we/dust/{code,audio,data}` owned by `we`; `dust-audio-common.tgz` (sha256-verified) unpacked to `/home/we/dust/audio/common`.

- [ ] **Step 1: Write `tests/image/maiden.bats`**

```bash
@test "maiden binary is aarch64 from the tag" { file "$ROOTFS/home/we/maiden/maiden" | grep -q 'ARM aarch64'; in_root /home/we/maiden/maiden version | grep -q "$MAIDEN_TAG"; }
@test "maiden web app present"   { [ -f "$ROOTFS/home/we/maiden/app/build/index.html" ]; }
@test "no Go toolchain left"     { ! in_root dpkg -s golang-go; }
@test "dust layout"              { for d in code audio data; do [ "$(stat -c %U "$ROOTFS/home/we/dust/$d")" = we ]; done; [ -d "$ROOTFS/home/we/dust/audio/common" ]; }
@test "maiden socket on port 80" { grep -q 'ListenStream=80' "$ROOTFS/etc/systemd/system/norns-maiden.socket"; }
```
- [ ] **Step 2: Build fs, run — expect FAIL**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Build fs, run — expect PASS**
- [ ] **Step 5: Commit** — `image: maiden v1.1.6 and default dust`

---

### Task 7: Pi 4 shield hardware — overlays, codec modules, boot config

**Files:**
- Create: `overlays/norns-snd-cs4270-overlay.dts`, `overlays/norns-snd-cs4271-overlay.dts`, `overlays/norns-buttons-encoders-overlay.dts`, `packages/monome-codecs-dkms/` (`dkms.conf`, `Makefile`, vendored `cs4270.c`, `cs4271.c`, `cs4271-i2c.c`, `cs4271.h`, plus any header they need from `include/sound/`, each with a header comment naming `raspberrypi/linux@CODEC_SRC_COMMIT` and GPL-2.0), `image/layer/norns-shield.yaml`, `image/layer/norns-shield.d/config.txt.in`, `tests/unit/overlays.bats`, `tests/image/shield.bats`
- Modify: `tests/helpers.bash` (add `dtbo NAME` = `fdtdump "$BATS_TMPDIR/NAME.dtbo"`; Ubuntu package `device-tree-compiler` gives `dtc`/`fdtdump` — add to CI deps)

**Interfaces:**
- Produces:
  - Overlays compiled with `dtc -@ -I dts -O dtb` into `/boot/firmware/overlays/norns-snd-cs4270.dtbo`, `norns-snd-cs4271.dtbo`, `norns-buttons-encoders.dtbo`. Derived from monome/linux `norns-5.10.y` (`monome-snd-4270`, `monome-snd-4271`, `norns-buttons-encoders`), with `compatible` for bcm2711, `simple-audio-card,name = "snd-rpi-monome"`, codec reset GPIO17, and the shield pin defaults from Global Constraints baked in (params kept as overrides). Encoder nodes named `knob1..3` under `/soc`, keys node named `keys`, so by-path names match matron.
  - DKMS module `monome-codecs/1.0` (`AUTOINSTALL="yes"`) building `snd-soc-cs4270.ko`, `snd-soc-cs4271.ko`, `snd-soc-cs4271-i2c.ko`; installed during the image build for **every** kernel in `/lib/modules`. `dkms` package installed.
  - `config.txt` (from `config.txt.in`): `dtparam=spi=on`, `dtparam=i2c_arm=on`, `dtparam=i2s=on`, `dtparam=audio=off`, `dtoverlay=norns-buttons-encoders`, and an empty managed block for Task 8 between `# BEGIN norns-codec` / `# END norns-codec`. No display overlay. `cmdline.txt` gains `spidev.bufsiz=8192`.

- [ ] **Step 1: Write `tests/unit/overlays.bats`** (compile each `.dts`, inspect with `fdtget`/`fdtdump`)

```bash
@test "overlays compile"           { for f in overlays/*.dts; do dtc -@ -I dts -O dtb -o "$BATS_TMPDIR/$(basename "$f" .dts).dtbo" "$f"; done; }
@test "cs4270 at 0x48, card name"  { o=$(dtbo norns-snd-cs4270); grep -q 'cirrus,cs4270' <<<"$o"; grep -q 'reg = <0x00000048>' <<<"$o"; grep -q 'snd-rpi-monome' <<<"$o"; }
@test "cs4271 at 0x10, card name"  { o=$(dtbo norns-snd-cs4271); grep -q 'cirrus,cs4271' <<<"$o"; grep -q 'reg = <0x00000010>' <<<"$o"; grep -q 'snd-rpi-monome' <<<"$o"; }
@test "encoders and keys named for matron" { o=$(dtbo norns-buttons-encoders); for n in knob1 knob2 knob3 keys; do grep -q "$n {" <<<"$o"; done; }
@test "shield pins are the defaults" { o=$(dtbo norns-buttons-encoders); for p in 0x04 0x1b 0x0c 0x19 0x18 0x17 0x16 0x1a 0x0d; do grep -q "$p" <<<"$o"; done; }
```
(`dtbo NAME` helper = `fdtdump` of the compiled file, defined in `tests/helpers.bash`.)
- [ ] **Step 2: `tests/run.sh unit` — expect FAIL; write the overlays; expect PASS; commit** — `overlays: shield audio and controls for Pi 4`
- [ ] **Step 3: Write `tests/image/shield.bats`**

```bash
@test "codec modules built for every kernel" { for k in $(ls "$ROOTFS/lib/modules"); do for m in snd-soc-cs4270 snd-soc-cs4271 snd-soc-cs4271-i2c; do in_root modinfo -k "$k" "$m" >/dev/null; done; done; }
@test "dkms rebuilds on kernel upgrade" { grep -q 'AUTOINSTALL="yes"' "$ROOTFS/usr/src/monome-codecs-1.0/dkms.conf"; in_root dpkg -s linux-headers-rpi-v8 linux-headers-rpi-2712 dkms >/dev/null; }
@test "overlays installed"   { for o in norns-snd-cs4270 norns-snd-cs4271 norns-buttons-encoders; do [ -f "$ROOTFS/boot/firmware/overlays/$o.dtbo" ]; done; }
@test "boot config"          { c="$ROOTFS/boot/firmware/config.txt"; for l in dtparam=spi=on dtparam=i2c_arm=on dtparam=i2s=on dtparam=audio=off dtoverlay=norns-buttons-encoders '# BEGIN norns-codec' '# END norns-codec'; do grep -qx "$l" "$c"; done; ! grep -q ssd1322 "$c"; }
@test "spidev buffer"        { grep -q 'spidev.bufsiz=8192' "$ROOTFS/boot/firmware/cmdline.txt"; }
```
- [ ] **Step 4: Build fs, run — expect FAIL**
- [ ] **Step 5: Implement the DKMS package and the layer (DKMS `install -k <kver>` for each kernel inside the chroot)**
- [ ] **Step 6: Build fs, run — expect PASS; check rootfs used bytes still ≤ 2.0 GB**
- [ ] **Step 7: Commit** — `image: shield codec DKMS modules, overlays and boot config`

---

### Task 8: Codec detection at boot

**Files:**
- Create: `scripts/norns-codec-detect`, `config/norns-codec-detect.service`, `tests/unit/codec-detect.bats`; Modify: `image/layer/norns-shield.yaml` (install + enable), `tests/image/shield.bats`

**Interfaces:**
- Produces `norns-codec-detect [--config PATH] [--probe CMD]`:
  - Default config `/boot/firmware/config.txt`; default probe `i2cget -y 1` (called as `<probe> 0x48` / `<probe> 0x10`; exit 0 = present). Only these two addresses are probed.
  - Found CS4270 (0x48) → managed block body becomes:
    ```
    [pi4]
    dtoverlay=norns-snd-cs4270
    [pi5]
    dtoverlay=norns-snd-cs4270-pi5
    [all]
    ```
    (CS4271 likewise with `cs4271`; `-pi5` overlays arrive in phase 2.)
  - Exit codes: `0` block already correct (no write); `10` block rewritten; `2` neither codec found (file untouched, message on stderr). Both found → prefer CS4270, exit as above, warn.
  - Only text between the markers changes; rest of the file byte-identical; write is atomic (temp file + `mv`) and `sync`ed.
- `norns-codec-detect.service`: `Type=oneshot`, `Before=norns-jack.service`, `After=systemd-modules-load.service`, `WantedBy=multi-user.target`; runs the script each boot; on exit 10 runs `systemctl reboot`; exits 0 and 2 are success (`SuccessExitStatus=2`).

- [ ] **Step 1: Write `tests/unit/codec-detect.bats`** (in the file's `setup`: fake probe = script exiting 0 iff its argument is in `$FAKE_I2C`; `$FIXTURE` = a config.txt with lines before and after an empty managed block, copied to `$CFG`; `detect` = `scripts/norns-codec-detect --config "$CFG" --probe "$FAKEPROBE"`; `block_has LINE` greps between the markers; `outside_block FILE` prints lines outside them)

```bash
@test "writes cs4270 block and exits 10"   { FAKE_I2C=0x48 run detect; [ "$status" -eq 10 ]; block_has dtoverlay=norns-snd-cs4270; block_has dtoverlay=norns-snd-cs4270-pi5; }
@test "second run is a no-op (no reboot loop)" { FAKE_I2C=0x48 detect || true; before=$(sha256sum "$CFG"); FAKE_I2C=0x48 run detect; [ "$status" -eq 0 ]; [ "$(sha256sum "$CFG")" = "$before" ]; }
@test "cs4271 replaces a stale cs4270 block" { FAKE_I2C=0x48 detect || true; FAKE_I2C=0x10 run detect; [ "$status" -eq 10 ]; block_has dtoverlay=norns-snd-cs4271; ! grep -q cs4270 "$CFG"; }
@test "nothing found leaves file untouched" { before=$(sha256sum "$CFG"); FAKE_I2C= run detect; [ "$status" -eq 2 ]; [ "$(sha256sum "$CFG")" = "$before" ]; }
@test "a PiSugar at 0x57/0x68 is ignored"  { FAKE_I2C="0x57 0x68" run detect; [ "$status" -eq 2 ]; }
@test "text outside markers preserved"     { FAKE_I2C=0x10 detect || true; diff <(outside_block "$CFG") <(outside_block "$FIXTURE"); }
```
- [ ] **Step 2: `tests/run.sh unit` — expect FAIL**
- [ ] **Step 3: Implement the script (bash) and unit**
- [ ] **Step 4: `tests/run.sh unit` — expect PASS**
- [ ] **Step 5: Add to `shield.bats`: `@test "codec detector enabled before jack" { in_root systemctl is-enabled norns-codec-detect.service; grep -q 'Before=norns-jack.service' "$ROOTFS/etc/systemd/system/norns-codec-detect.service"; }`; build fs; run — expect PASS**
- [ ] **Step 6: Commit** — `image: detect shield codec revision at boot`

---

### Task 9: Acceptance checklist and first release

**Files:**
- Create: `docs/testing/acceptance.md`; Modify: `README.md` (link it, "Supported hardware" table: Pi 4 + shield/shieldXL = phase 1; Pi 5 = boots, shield support pending)

**Interfaces:**
- Consumes: everything above.
- `acceptance.md` — the spec's checklist as tick boxes, each with how to check it, for **Pi 4 + shieldXL**: first boot grows root fs (`df -h /`); codec detected and single reboot happens once; screen shows norns; K1–K3 and E1–E3 respond; audio in→out at 48 kHz/128 with no xruns (`journalctl -u norns-jack`); maiden at `http://norns.local` runs a script; PolyPerc plays; Wi-Fi connect + hotspot; USB grid/MIDI detected; SMB share `\\norns.local\dust` reachable as `we`/`sleep`; SYSTEM > UPDATE leaves `~/norns` unchanged (`git -C ~/norns status`); clean shutdown; `sudo apt update && sudo apt full-upgrade` then reboot — audio still works. **Pi 5 smoke:** boots to SSH login.

- [ ] **Step 1: Write `acceptance.md` and README updates; commit** — `docs: acceptance checklist and supported hardware`
- [ ] **Step 2: Open PR `trixie-image` → `sethbc/norns-image` main (`gh pr create --repo sethbc/norns-image --base main`); CI green**
- [ ] **Step 3: After Seth merges, tag `v0.1.0` on `sethbc/norns-image`; CI publishes the release**
- [ ] **Step 4: Hand Seth the release link and the checklist; record results in `docs/testing/acceptance.md` (date, hardware, pass/fail per line); file follow-ups for failures**
