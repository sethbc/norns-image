# norns image on Debian 13 (trixie) — design

Status: draft for review · 2026-11-03 · fork: `sethbc/norns-image`

## Intent

Today this repo is a manual recipe: flash stock Raspbian Buster, then hand-run
`build-dev-image.md` and `setup.sh` over serial. It targets an OS that is three
Debian releases old and a held, custom kernel.

We want a **reproducible, scripted build** that produces **one flashable image**
on Raspberry Pi OS trixie (Debian 13, arm64) that runs the **unchanged, released**
norns software stack on modern Raspberry Pi hardware, starting with norns shields
on the Pi 4 and Pi 5. The work lives in, and is released from, Seth's fork.

## Goals

1. One combined arm64 image that boots and runs norns on:
   - Raspberry Pi 4 / Pi 5 + stock norns shield, **both codec revisions**:
     pre-211028 (CS4270, i2c 0x48) and 211028+ (CS4271, i2c 0x10)
   - Pi 4 / Pi 5 + [shieldXL](https://github.com/okyeron/shieldXL), including its hardware TRS MIDI
2. The image is built by a script from a declarative config in this repo; the
   same commit produces an equivalent image, with an SBOM and package manifest.
3. CI on the fork builds the image and attaches it (plus checksum, SBOM,
   manifest) to a GitHub release.
4. Uses the **stock Raspberry Pi kernel** and keeps normal kernel updates working
   (no `raspberrypi-kernel hold`).
5. Designed so the original norns (CM3/CM3+) can be added later as another
   hardware profile in the same image.

## Non-goals

- Modifying norns, maiden, SuperCollider, or libmonome source. We build monome's
  **released versions unchanged**. Where trixie or new hardware needs something
  different, we adapt *underneath* them (kernel module, overlay, udev rule,
  vendored library), never by patching them.
- Supporting the original norns (CM3) in the first release (phase 2, below).
- Pi 3 / 32-bit (armhf) images.
- A desktop, HDMI UI, or PipeWire. Audio stays on JACK as today.
- Upstreaming to monome. **No PRs, issues, or pushes to `monome/*`.**

## Anti-goals (failure even if it "works")

- A forked/custom kernel we must rebuild for every Pi kernel update.
- Manual steps between "clone repo" and "flashable image".
- An image that can't plausibly fit the CM3's 4 GB eMMC with room for `dust`
  (would block phase 2).
- Copying code we don't have a license to use (see Constraints).

## Constraints

- **Fork only.** All branches, PRs, and releases go to `sethbc/norns-image`.
  `gh pr create` on a fork defaults to the *parent* repo — always pass
  `--repo sethbc/norns-image` (and `--base main`). The local clone has an
  `upstream` remote pointing at monome; never push to it.
- **Licensing.**
  - `monome/norns-image` (and therefore this fork) has **no license file**.
    New files we write are ours; note this in the README, don't relicense
    monome's existing files.
  - `The-XOR/norns-image` has no license → reference for ideas only, **copy
    nothing**. (It targets a different DIY device on Buster anyway.)
  - Reusable: `okyeron/shieldXL` (GPL-3), `monome/linux` (GPL-2),
    mainline Linux `sound/soc/codecs/cs4270.c` (GPL-2),
    `raspberrypi/rpi-image-gen` (BSD-3), libgpiod (LGPL-2.1).
- **Build host.** Local builds run on `amd64-mini` (x86_64, Ubuntu 26.04, 16
  cores, Docker, passwordless sudo) under QEMU user emulation, which
  `rpi-image-gen` says is "not formally supported". It works (spike below).
  CI uses GitHub's native arm64 runners, which is the supported path.
  Working dir on that host: `~/src/norns-image`; clone any other repos into `~/src`.
- **Space budget.** The image must stay small enough that a CM3 variant with
  4 GB eMMC is feasible later. *(Claude's call)* CI fails the build if the
  root filesystem's used space exceeds **2.0 GB**; report usage per build.

## What we learned (research + spike, 2026-11-03)

### Spike: rpi-image-gen on amd64-mini
- `rpi-image-gen` @ `ff5fb45` built `config/trixie-minbase.yaml` in **5m38s**
  after `install_deps.sh` + `qemu-user-binfmt`. Output: `.img.zst`, SBOM,
  manifest, `SOURCE_DATE_EPOCH`.
- Root fs used: **643 MB** (1.5 GB partition). Plenty of headroom.
- Harmless noise: `/proc`/`/sys` mount fallbacks (unprivileged namespace);
  a `dpkg --purge sudo` step that fails because `raspinfo` depends on it.
- Trixie ships **kernel 6.18** (`6.18.50+rpt`), not 6.12.
- The stock `rpi5` device layer only installs the Pi 5 kernel (`kernel_2712.img`);
  the combined image must also install the Pi 4 kernel (`linux-image-rpi-v8`).

### How norns talks to the shield hardware (norns v2.9.4)
- **OLED**: matron drives the SSD1322 **from userspace** — `/dev/spidev0.0`
  plus libgpiod lines 5 (D/C) and 6 (reset) on `gpiochip0`. **No display
  kernel driver** is needed (don't load fbtft or DRM ssd130x on spi0.0).
- **Keys/encoders**: evdev devices at fixed paths (from `matronrc.lua`):
  `/dev/input/by-path/platform-keys-event`,
  `/dev/input/by-path/platform-soc:knob{1,2,3}-event`.
- **Audio**: JACK opens `hw:sndrpimonome`; the overlay must name the card
  `snd-rpi-monome`. monome's `monome-snd-4270` overlay is just
  `simple-audio-card` + `cirrus,cs4270` at i2c1 0x48 with reset on GPIO17.
- **Platform**: `platform.c` reads `/sys/firmware/devicetree/base/model`;
  a Pi 5 maps to `PLATFORM_OTHER`, which takes the shield (non-factory) path
  for screen orientation. Expected to be fine; verify.
- Headphone amp (i2c 0x60) is norns-only; on shields it's absent (as today).

### What trixie / the stock Pi kernel provide
| Need | Status in trixie / rpi 6.18 |
|---|---|
| spidev, GPIO chardev **v1 uAPI** (`CONFIG_GPIO_CDEV_V1=y`) | ✅ |
| `rotary-encoder`, `gpio-keys` drivers + stock overlays | ✅ (modules) |
| `simple-audio-card` | ✅ |
| **CS4270 codec driver** | ❌ `CONFIG_SND_SOC_CS4270` not set in bcm2711 or bcm2712 configs |
| `midi-uart0` and `midi-uart0-pi5` overlays | ✅ |
| libgpiod | ⚠️ 2.2.1 — **v2 API**; matron uses the removed **v1 API** |
| Lua 5.3 (`lua53.pc`), liblo, nanomsg 1.1.5, jackd2 1.9.22, boost 1.83, cairo, libevdev, avahi-compat | ✅ |
| SuperCollider 3.13.0 + sc3-plugins | ✅ packaged |
| libmonome, amidiminder, ttymidi | ❌ not packaged — build from source |
| `usbmount` | ❌ gone since bookworm |

## Approaches considered

**Build tool**
- **A. rpi-image-gen** (chosen): Raspberry Pi's current generator; declarative
  YAML layers on an mmdebstrap minimal base; reproducibility and SBOM built in;
  layers map onto hardware profiles; minimal base suits the 4 GB goal.
  Trade-off: x86 host via QEMU is unsupported (works in practice; CI on arm64).
- **B. pi-gen**: builds Raspberry Pi OS itself; shell stages; Docker on x86.
  Fuller base means more trimming; slower; less declarative.
- **C. Remaster the official Lite image**: fastest and closest to today's
  `setup.sh`, but inherits everything in Lite — works against the space goal.

**Kernel / drivers**
- **1. Stock Pi kernel + small out-of-tree pieces** (chosen): device-tree
  overlays from source in this repo, plus a DKMS-built `snd-soc-cs4270` module.
  Kernel updates keep working.
- **2. Rebase `monome/linux` onto rpi-6.18.y and ship a custom kernel**:
  monome's historical approach; everything in-tree, but a kernel fork to
  maintain and a held kernel. Rejected (anti-goal).

Seth picked **A + 1**. The research then showed the OLED needs no kernel driver
at all, which shrinks option 1 to: overlays + DKMS codec modules.

**Running unchanged norns on arm64**
- **(a) Build-only adaptation** (chosen): compiler wrapper drops `-mfpu=*`
  and `-Werror`; source untouched; everything 64-bit.
- **(b) monome's prebuilt armhf binaries**: truly unchanged and keeps the
  stock updater working, but needs a 32-bit userland and forces the Pi 5
  onto the 4K-page kernel.
- **(c) Source patches in this repo**: violates "unchanged".

## The design (decided)

### Repo layout (proposed)
```
image/                     rpi-image-gen config + our layers
  norns.yaml               top-level config (device, image, layers)
  layer/norns-base/        user `we`/`sleep`, hostname `norns`, packages, trims
  layer/norns-runtime/     build+install pinned norns, maiden, libmonome, SC bits
  layer/norns-shield/      overlays, config.txt fragments, cs4270 DKMS, udev
  layer/norns-shieldxl/    ttymidi, amidiminder, MIDI services + toggle
  layer/norns-cm3/         (phase 2)
overlays/                  .dts sources we compile (shield: pi4 + pi5 variants)
packages/                  build recipes for vendored pieces (cs4270-dkms,
                           libgpiod1, libmonome, ttymidi, amidiminder)
config/                    existing systemd units/config, modernized
versions.env               every pinned upstream: tag + commit/sha256
build.sh                   one entry point: local or CI
.github/workflows/         CI build + release
```
`setup.sh` and `build-dev-image.md` are retired once their content lives in
layers; keep a short doc pointing to the new flow.

### Hardware profiles and the combined image
- One arm64 image installs **both** `linux-image-rpi-v8` (Pi 4) and
  `linux-image-rpi-2712` (Pi 5). `config.txt` uses `[pi4]` / `[pi5]` sections
  to select per-board overlays.
- **Shield (all boards)**
  - `dtparam=spi=on` (spidev0.0 for matron), `dtparam=i2c_arm=on`,
    `dtparam=i2s=on`, `dtparam=audio=off`.
  - Audio overlays derived from monome's `monome-snd-4270` and
    `monome-snd-4271` (both `simple-audio-card`, card name `snd-rpi-monome`,
    codec reset on GPIO17), each with a **Pi 5 variant** (RP1 I2S / pinctrl
    differ from BCM2711).
  - Codec drivers: neither `CONFIG_SND_SOC_CS4270` nor `..._CS4271` is set in
    the Pi kernels. A `monome-codecs-dkms` package builds mainline `cs4270.c`
    and `cs4271.c` (+ `cs4271-i2c.c`) out of tree via DKMS for every installed
    kernel flavour, so kernel upgrades rebuild them. *(Claude's call: DKMS
    over prebuilt modules, accepting gcc + headers in the image; revisit for
    CM3 in phase 4.)*
  - **Codec auto-detect** *(Claude's call)*: the shield has no ID EEPROM, but
    the codecs sit at different I2C addresses. A first-boot oneshot probes
    i2c-1 for 0x48 vs 0x10 (ignoring other devices such as a PiSugar at
    0x57/0x68), writes the matching `dtoverlay=` line into
    `/boot/firmware/config.txt`, and reboots once. CS4271 path is untested
    on hardware (Seth has none) — review-only until someone tests it.
  - `cmdline.txt` keeps `spidev.bufsiz=8192` (matron sends full frames).
  - Keys/encoders overlay with **Pi 4 and Pi 5 variants**, pins from the
    shield config (E1 4/27, E2 12/25, E3 24/23, K1 22, K2 26, K3 13). Device
    nodes must yield the exact `/dev/input/by-path/...` names in
    `matronrc.lua`; if that's impractical on Pi 5's device tree, **udev
    symlinks** provide those names instead (shim, not a norns change).
  - GPIO 5/6 must be free for matron (no display driver claims them), and
    must be on `gpiochip0` on both boards — verify on Pi 5 / 6.18; if not,
    a udev symlink or naming shim is needed.
- **Shield XL MIDI**
  - `midi-uart0` on Pi 4, `midi-uart0-pi5` on Pi 5; serial console moved off
    GPIO 14/15; `ttymidi` + `amidiminder` (built from source for arm64; the
    upstream `.deb` is armhf) as in okyeron's `install-midi.sh`.
  - **Toggle:** if the stock shield leaves GPIO 14/15 unused, enable MIDI
    unconditionally (no switch). Otherwise ship it off and enable it with one
    line in `config.txt` on the boot partition (documented). Builder verifies
    against the shield schematic.

### Running unchanged norns on trixie (shims)
- **libgpiod v1**: build libgpiod **1.6.x** from source as a private package
  (e.g. prefix `/opt/norns/libgpiod1` with its own `.pc`), and point matron's
  configure at it via `PKG_CONFIG_PATH`. Trixie's libgpiod 2 stays installed
  for everything else. The kernel still exposes the v1 chardev ABI.
- **libmonome**: build the pinned monome release from source (not in trixie).
- **norns**: build the pinned release tag from source with `./waf` (arm64);
  run `sc/install.sh` as today. Unchanged norns does **not** build for arm64
  as released: `matron/wscript` (v2.9.4; `norns/wscript` in 3.x) always adds
  `-mfpu=neon`, which aarch64 GCC rejects, and the top-level `wscript` adds
  `-Werror`, which trixie's GCC 14 is likely to trip. **Decided (Seth):**
  adapt the *build*, not the source — a thin compiler wrapper (on `PATH` /
  `CC`/`CXX` for the norns build only) that drops `-mfpu=*` and `-Werror`.
  The release tree stays byte-identical to the tag. Rejected: running
  monome's prebuilt armhf binaries (needs a 32-bit userland, costs space,
  forces Pi 5 onto the 4K-page `kernel8.img`); carrying source patches.
- **On-device SYSTEM > UPDATE** must not break the image. Stock
  `update/update.sh` deletes `~/norns` and `~/maiden`, installs monome's
  armhf binaries and `.deb`s, and edits `/boot/config.txt` /
  `/boot/cmdline.txt` (wrong paths on trixie). The release list is fetched
  from monome's GitHub, so it can't be redirected without patching norns.
  **Decided (Seth):** neutralise it from outside norns — the script aborts
  with "needs new disk image" when `~/version.txt` is below `220306`, so the
  image ships a `~/version.txt` that trips that guard (builder confirms the
  menu still behaves sensibly; pick a better external guard if one exists).
  Updates are delivered by flashing new releases from the fork; an
  image-specific updater is possible later, out of scope now.
- **maiden**: build the pinned tag from source for arm64 (no release assets
  for 1.1.6).
- **SuperCollider**: prefer trixie's 3.13.0 packages; fall back to building
  the version norns expects from source only if norns' SC classes fail.

### Default versions (Claude's call; change in `versions.env`)
- norns **v2.9.4** (latest non-prerelease; 3.x is still marked prerelease).
  The 3.x line is a one-line switch once stable.
- maiden v1.1.6, libmonome v1.4.11, rpi-image-gen pinned to a commit.

### OS config modernization (from today's `setup.sh` / `config/`)
- Boot files live in `/boot/firmware` (not `/boot`).
- polkit `.pkla` → JS rule in `/etc/polkit-1/rules.d/`.
- `usbmount` → udev + `systemd-mount` (or udisks2) rule for USB sticks
  (norns SYNC menu needs auto-mount at the path norns expects — verify path).
- `samba` restarts via `systemctl restart smbd`; `pppd-dns`, `dphys-swapfile`,
  `triggerhappy`, `exim4`, plymouth purges become "don't install" in the
  minimal base instead of purges.
- rsyslog: drop; journald with size limits only.
- NetworkManager is trixie's default; keep the `config/network-manager/*`
  files; hotspot behaviour stays as norns' own scripts implement it.
- systemd units in `config/` carry over; check paths (`/usr/bin/sclang`,
  `jack_wait`) against trixie packages.
- Keep `we` / `sleep`, hostname `norns`, SSH on, as today's images.

### Reproducibility
- Pin every input: rpi-image-gen commit, each upstream tag **and** commit SHA
  (or tarball sha256) in `versions.env`.
- `SOURCE_DATE_EPOCH` from the last git commit.
- Publish SBOM + manifest with each release so drift is visible.
- Apt: Debian packages can be pinned via snapshot.debian.org; the Raspberry Pi
  archive has no snapshot service, so "reproducible" means *equivalent and
  fully recorded*, not bit-identical. Bit-identical is not a goal.

### CI and releases
- GitHub Actions on `ubuntu-24.04-arm` in `sethbc/norns-image`: build on PRs
  (artifact) and on tags (release with `.img.zst`, `.sha256`, SBOM, manifest).
- `build.sh` runs identically on `amd64-mini` and in CI.

### Phases
0. **Skeleton**: our config builds a trixie image with both kernels, `we`
   user, SSH, our layers wired in — locally and in CI.
1. **Pi 4 + shield**: norns boots; screen, keys, encoders, audio in/out,
   maiden at `http://norns.local`, SC engines load.
2. **Pi 5 + shield**: Pi 5 overlay variants, GPIO chip check, same checklist.
3. **Shield XL MIDI** on both boards.
4. **CM3 norns** (separate design pass): battery gauge, power latch
   (`gpio-poweroff` + `dt-blob.bin`), headphone amp, CM3 key/encoder pins,
   RTL8192CU wifi, 4 GB eMMC, 1 GB RAM on arm64.

5. **PiSugar 3 Plus battery** (Seth has one fitted; later phase, own layer
   `norns-pisugar`): install PiSugar's `pisugar-server` (GPL-3,
   `PiSugar/pisugar-power-manager-rs`, pin a release, arm64) for battery
   status, safe shutdown on low battery, and its RTC. It sits on i2c-1
   (0x57, RTC 0x68) alongside the codec — no address clash, but the codec
   auto-detect must only look at 0x48/0x10. Showing the charge level in the
   norns UI is out of scope unless it can be done without patching norns
   (matron's battery code targets the CM3's BQ27441). Verify Pi 5 fit and
   support. Opt-in like the shieldXL MIDI, since it can't be auto-detected
   safely without probing — builder decides whether probing 0x57 is enough.

### Acceptance checklist per hardware target
Boots to the norns screen; all 3 keys and 3 encoders respond; audio passes
in→out with no xruns at 48 kHz/128; maiden loads and runs a script; an engine
(e.g. PolyPerc) plays; Wi-Fi connect + hotspot; USB grid/MIDI device detected;
SYNC to USB stick works; clean shutdown; `apt upgrade` of the kernel keeps
audio working (DKMS rebuild). Shield XL adds: TRS MIDI in and out.

## Left to the builder
- Exact rpi-image-gen layer mechanics, file names, and `build.sh` shape.
- Whether keys/encoders use our own overlay or stock `rotary-encoder` /
  `gpio-key` overlays + udev symlinks — whichever reliably yields matron's
  paths on both boards.
- Whether vendored pieces are `.deb`s built in a prior CI step or built inside
  the image build.
- Trimming choices to keep the image small.

### Test hardware
Seth has a **Pi 4 + shieldXL** and a **Pi 5 + shieldXL**, plus a
**PiSugar 3 Plus** battery (phase 5). The shieldXL is
electrically the 210330 CS4270 shield plus UART MIDI, so these cover every
shield code path except "stock shield with MIDI disabled"; that path is
verified by booting with MIDI toggled off (if a toggle exists) and by review.
No CM3 norns is on hand yet (needed before phase 4). On-device acceptance
checks are run by Seth by hand from the checklist; the builder works on
`amd64-mini` and does not have remote access to the Pis unless Seth adds it.
