# asahi-atomic-niri

A Fedora Asahi Remix Atomic (bootc) image with the **niri** compositor and
**Noctalia** shell for Apple Silicon Macs. The same tiling Wayland
desktop as [my bazzite image](https://github.com/crispywaffles666/bazzite-niri),
built as a bootable container on top of Fedora Asahi Remix.


## What's included

Built on `quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44`, which
ships no desktop environment and retains the full Asahi hardware stack (Asahi
kernel, Mesa, firmware, `update-m1n1`, `dracut-asahi`, `alsa-ucm-asahi`,
U-Boot).

**Compositor / login:** niri, xwayland-satellite, greetd, tuigreet

**Shell:** Noctalia

**Terminals:** alacritty, ghostty

**Desktop apps:** nautilus, gnome-keyring, seahorse, xdg-desktop-portal-gnome,
xdg-desktop-portal-gtk, geany, brave-origin

**Tools:** brightnessctl, playerctl, inotify-tools, wl-clipboard, wtype,
pavucontrol, cava, satty, xterm, zsh, bat, micro, ripgrep, stow, yazi,
starship, fastfetch, libnotify, xdg-utils, overpass-fonts, pulseaudio-utils,
tailscale, uupd

**Containerized dev environments:** distrobox (with podman), plus a shared
`/etc/distrobox/distrobox.ini` assemble manifest with arm64-compatible Fedora,
Ubuntu, Debian, and Arch presets.

**Flatpak runtime:** flatpak + a system Flathub remote (added at first boot).
Per-user, first-login installs of **Flatseal**, **Warehouse**, and **Smile**.

**Host-native multimedia (software decode):** ffmpeg-free and the Fedora
`gstreamer1-plugins-{base,good,bad,ugly}-free` set for H.264/HEVC/VP9/AV1/AAC.
The Asahi Mesa/kernel/firmware stack is untouched; Asahi's hardware video
decode (AVD → VA-API) is not yet bundled upstream, so these provide dependable
software decode.

**Desktop plumbing:** udisks2, gvfs (+ MTP / archive / FUSE backends),
gnome-disk-utility, CUPS (printing), bluez + blueman (Bluetooth),
power-profiles-daemon (CPU performance profiles), file-roller (archives),
evince (PDF), eog (image viewer).

User dotfiles and configs (`/etc/skel`): niri (`config.kdl` + `cfg/`), Noctalia,
bash/zsh/starship, alacritty, ghostty, micro, geany, btop, cava, fastfetch,
satty, yazi, and the helper scripts `niri-overview-autoclose.sh`,
`screenshot-notify.sh`, and `smile-paste.sh`.

## Distrobox

Create the preset development containers (one-time):

```bash
distrobox assemble create --file /etc/distrobox/distrobox.ini
# or individually, e.g.:  distrobox assemble create --file /etc/distrobox/distrobox.ini fedora
```

All presets use official multi-arch images that publish a `linux/arm64`
manifest and run natively on Apple Silicon. Development containers are updated
manually (`distrobox upgrade <name>`); uupd's distrobox module stays disabled.

## Automatic brightness (ambient light sensor)

`asahi-brightnessd` (built into the image from pinned, MIT-licensed
[upstream](https://github.com/craig-miller/asahi-brightnessd) source at image
build time) is an image-owned system daemon that drives **both** backlights
from the Apple Silicon ambient light sensor:

- the **display** backlight rises with ambient light (like macOS)
- the **keyboard** backlight is the inverse — bright in the dark, off once the
  room is bright enough

It polls `/sys/bus/iio/devices/iio:deviceN/in_illuminance_input`, reads the AC
power-supply state, and writes to
`/sys/class/backlight/apple-panel-bl/brightness` and
`/sys/class/leds/kbd_backlight/brightness`.

**Manual changes are respected as overrides.** A manual change from Noctalia
or `brightnessctl` pauses auto control for *that channel only* — display and
keyboard override independently. Auto control resumes for a channel once the
ambient light shifts by roughly 75% (or a small absolute amount in low light).

`iio-sensor-proxy` is installed alongside as the standard Fedora sensor
userspace, so `monitor-sensor` is available for diagnostics. It does **not**
control brightness in this image — `asahi-brightnessd` does.

Diagnostics:

```sh
systemctl status asahi-brightnessd
journalctl -u asahi-brightnessd
monitor-sensor
find /sys/bus/iio/devices -name in_illuminance_input -print
```

**ALS availability depends on the Asahi kernel and per-machine firmware.** The
`aop-als` IIO driver ships in the Asahi kernel (6.19+), but the sensor needs
factory calibration firmware that is per-machine and cannot be redistributed.
On Fedora Asahi, get it by booting macOS / macOS Recovery, re-running the
Asahi installer, and choosing **Rebuild vendor firmware package**. The daemon
service skips machines without the panel backlight and retries harmlessly
(never blocking boot) until the ALS is available, so a missing/uncalibrated
sensor cannot break the image.

## Homebrew, Tailscale, and automatic updates

Three convenience features are layered on top of the base:

- **Homebrew** — staged image-owned at build time and copied into
  `/var/home/linuxbrew` on first boot by `brew-setup.service`. Managed as the
  default user (UID 1000); brew analytics are disabled.
- **Tailscale** — installed from Tailscale's official RPM repository with
  `tailscaled.service` enabled. Run `sudo tailscale up` to join your tailnet.
- **keyd** — installed from the `alternateved/keyd` COPR with `keyd.service`
  enabled; system-wide key remapping (remap keys/layers at the evdev level,
  config in `/etc/keyd/default.conf`, reload with `sudo keyd reload`).
- **Automatic updates** — `uupd` (from the Universal Blue `ublue-os/packages`
  COPR) runs daily via `uupd.timer` and updates the OS via bootc, flatpaks (a
  system Flathub remote is added on first boot by `flathub-setup.service`), and
  brew packages. Config lives at `/etc/uupd/config.json`.

  **Update safety:** uupd *stages* OS updates (via bootc/rpm-ostree) but never
  reboots automatically. To harden against any auto-apply/reboot driver the
  base image might ship, this image explicitly **masks**
  `bootc-fetch-apply-updates.timer` and `rpm-ostreed-automatic.timer`, so the
  *only* automatic OS-update path is uupd's stage-only flow. You decide when to
  reboot into a staged deployment (see the boot-safety section below).

Homebrew, tailscale, and the flathub system remote assume the machine's primary
user is UID 1000 (the Fedora/Asahi default).

## Image signing

Images are signed with **cosign**. The private key is stored in the GitHub
repository secret `SIGNING_SECRET`; the matching public key is committed as
`cosign.pub`. CI signs every `main`-branch build.

Each build publishes three tags, all cosign-signed:

- `latest` — latest build
- `<commit-sha>` — exact commit
- `44-YYYYMMDD` — human-readable date (e.g. `44-20260831`), useful for
  pinning/rolling back with `bootc switch` to a known-good historical build.

Verify a pulled image:

```bash
cosign verify \
  --key cosign.pub \
  ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

**Runtime signature enforcement:** this image ships the container
policy/`registries.d` configuration so that, once the image's own `/etc` is in
place after the first (unverified-transport) rebase, every subsequent pull of
`ghcr.io/crispywaffles666/asahi-atomic-niri` through bootc/rpm-ostree is
verified against this committed public key (see the boot-safety section for the
two-stage rebase). Unrelated registries used by Podman/Distrobox are left
permissive.

To roll back to a specific dated build:

```bash
sudo bootc switch \
  ghcr.io/crispywaffles666/asahi-atomic-niri:44-20260831
```

# Installing asahi-atomic-niri

> [!WARNING]
> This is an experimental installation procedure.
>
> Fedora Asahi Atomic itself is experimental, and the procedure below uses
> `bootc install to-existing-root` in a way that is not currently an officially
> supported Fedora Asahi installation path.
>
> It has been tested on an M2 MacBook, but expect to need macOS or another
> working Asahi installation for recovery.
>
> Keep macOS recovery available. Keeping an existing Linux installation until
> the Atomic system is proven working is strongly recommended.
>
> For me, it worked on the first attempt without bricking anything, but required several steps and a lot of troubleshooting. My process is documented below.

## Overview

The tested installation path is:

```text
macOS
  ↓
Fedora Asahi Remix 44 Minimal
  ↓
bootc takeover with Fedora Asahi base-atomic:44
  ↓
repair Asahi ESP boot.bin + vendor firmware
  ↓
Fedora Asahi Atomic
  ↓
asahi-atomic-niri
```

The awkward part is the Minimal → Atomic takeover.

Generic `bootc install to-existing-root` successfully creates the OSTree/bootc
deployment, but in testing it did not preserve all of the per-install Asahi
state living on the ESP.

Specifically, the takeover removed or failed to preserve:

- `/m1n1/boot.bin`
- the per-machine `vendorfw` payload

Both must be restored before the resulting Atomic install is fully usable.

## 1. Install Fedora Asahi Remix Minimal

From macOS:

```sh
curl https://alx.sh | sh
```

Install:

```text
Fedora Asahi Remix 44 Minimal
```

Boot it and complete the normal first-boot setup.

Verify that the system works before continuing:

```sh
uname -a
findmnt -T /
findmnt -T /boot
findmnt -T /boot/efi
nmcli device
```

A normal Fedora Asahi Minimal installation should have:

```text
/          Btrfs
/boot      ext4
/boot/efi  FAT32 EFI - ASAHI
```

Do not continue until Fedora Minimal boots successfully.

## 2. Install Podman

```sh
sudo dnf install -y podman
```

## 3. Convert the Fedora root to Atomic

Run the Fedora Asahi Atomic base image as the bootc installer:

```sh
sudo podman run --rm \
  --privileged \
  --pid=host \
  --ipc=host \
  --security-opt label=disable \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev \
  -v /:/target \
  quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44 \
  bootc install to-existing-root \
  --acknowledge-destructive
```

A successful takeover ends with:

```text
Installation complete!
```

Generic EFI/`efibootmgr` warnings may also appear.

## 4. Expected first boot failure: missing m1n1/boot.bin

After the takeover, the first reboot may stop in m1n1 with:

```text
Chainloading <PARTUUID>;m1n1/boot.bin
Chainload failed: FATError(NotFound)
No valid payload found
```

This means stage-1 m1n1 still knows which ESP belongs to the installation, but
the takeover removed:

```text
/m1n1/boot.bin
```

from that ESP.

The tested recovery method was to boot another working Asahi Linux installation
and reconstruct the Fedora ESP's `m1n1/boot.bin` using Fedora Asahi's m1n1,
U-Boot, and matching kernel DTBs.

Do not write another installation's `boot.bin` to the Fedora ESP.

Identify the Fedora ESP by PARTUUID, not by remembered partition number.

Example inspection:

```sh
lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS
blkid
```

After `boot.bin` has been restored, Fedora Atomic should boot.

> [!NOTE]
> This recovery step should eventually be automated. Until then, consider the
> Minimal → Atomic takeover an expert-only procedure.

## 5. Recover or defer creation of the primary user

The bootc takeover may not preserve the user created by Fedora Minimal.

If necessary, use a temporary systemd debug shell from the GRUB kernel command
line:

```text
systemd.debug_shell=1
```

Boot normally, then switch to TTY9:

```text
Ctrl+Alt+F9
```

If SELinux prevents account modification:

```sh
setenforce 0
```

If you want to create the user immediately, replace `<username>` with your
desired login name:

```sh
useradd -u 1000 -U -G wheel -m -d /var/home/<username> <username>
passwd <username>
```

Verify:

```sh
id <username>
```

Expected:

```text
uid=1000(<username>) gid=1000(<username>) groups=1000(<username>),10(wheel)
```

Remove `systemd.debug_shell=1` after recovery. It exposes an unauthenticated
root shell.

If the goal is to inherit this image's `/etc/skel`, it is better to delay final
user creation until after rebasing to `asahi-atomic-niri`.

## 6. Restore Apple vendor firmware

After the bootc takeover, the Broadcom hardware may be visible but Wi-Fi can be
missing from NetworkManager:

```sh
nmcli device
```

may show only:

```text
lo
```

while:

```sh
lspci -nnk
```

still shows the BCM4387 device and `dmesg` contains `brcmfmac` firmware failures
with error `-2`.

From macOS, run the Asahi installer again:

```sh
curl https://alx.sh | sh
```

Choose:

```text
v: Rebuild vendor firmware package
```

and select the Fedora Atomic installation.

### Known installer issue after bootc takeover

The takeover may have removed:

```text
/EFI - ASAHI/asahi/
```

from the Fedora ESP.

In that case the firmware rebuild can successfully copy the actual vendor
firmware and then crash while trying to write:

```text
/asahi/all_firmware.tar.gz
```

with:

```text
FileNotFoundError: ... /asahi/all_firmware.tar.gz
```

The useful `vendorfw` payload may already have been installed.

Reboot Fedora and check:

```sh
nmcli device
```

If `wlan0` exists, the runtime firmware repair succeeded.

If desired, the missing ESP directory can be recreated from macOS before
rerunning the firmware rebuild:

```sh
diskutil mount <FEDORA_ESP>
sudo mkdir -p "/Volumes/EFI - ASAHI/asahi"
```

Never guess the ESP device. Identify it first.

## 7. Verify stock Atomic

Once the system boots and networking works:

```sh
bootc status
rpm-ostree status
uname -a
nmcli device
```

At this point the system should report:

```text
quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44
```

as its booted image.

## 8. Rebase to asahi-atomic-niri

The first rebase must use the unverified transport because this image's
signature policy is not installed yet:

```sh
sudo rpm-ostree rebase \
  ostree-unverified-registry:ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

Reboot:

```sh
sudo systemctl reboot
```

## 9. First custom-image boot

Check:

```sh
bootc status

systemctl status \
  asahi-atomic-niri-update-m1n1.service \
  --no-pager -l

journalctl -b \
  -u asahi-atomic-niri-update-m1n1.service \
  --no-pager
```

The image's deployment-aware m1n1 service should rebuild `boot.bin` using the
DTBs belonging to the currently booted deployment.

If it succeeds, reboot again:

```sh
sudo systemctl reboot
```

This second reboot is the first boot using the newly generated
m1n1/U-Boot/DTB payload.

## 10. Enable signature enforcement

After successfully booting the custom image:

```sh
sudo rpm-ostree rebase \
  ostree-image-signed:docker://ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

Then:

```sh
sudo systemctl reboot
```

Future updates of this image are now verified against the public signing key
shipped by the image.

## 11. Create the primary user

If you deliberately postponed user creation so that the custom image's
`/etc/skel` is used, replace `<username>` with your desired login name:

```sh
sudo useradd \
  -u 1000 \
  -U \
  -G wheel \
  -m \
  -d /var/home/<username> \
  <username>

sudo passwd <username>
```

Verify:

```sh
id <username>
ls -la /var/home/<username>
```

The new home should be populated from the custom image's `/etc/skel`.

## What the takeover currently breaks

Observed during the first successful M2 installation:

| Component | Result |
|---|---|
| OSTree deployment | Works |
| Fedora `/boot` conversion | Works |
| GRUB | Works |
| Apple boot-policy stub | Preserved |
| ESP `/m1n1/boot.bin` | **Lost, manual repair required** |
| Vendor firmware | **Lost, rebuild required** |
| Wi-Fi | Returns after vendor firmware rebuild |
| Existing local user | **Not preserved** |
| Custom image rebase | Works |
| `/etc/skel` on user creation | Works |
| Custom m1n1 refresh | Must be verified after first custom boot |

## Recovery philosophy

Do not treat the ESP as part of the atomic root filesystem.

There are three independent pieces of state:

```text
Apple boot policy / stub APFS
        ↓
Asahi ESP
  - m1n1/boot.bin
  - vendorfw
        ↓
OSTree / bootc deployment
```

A successful bootc deployment does not imply that the Asahi ESP is valid.

Until the bootstrap procedure is automated, keep macOS recovery and preferably
another working Asahi install available.

## Building

CI builds natively on an `ubuntu-24.04-arm` runner (no emulation), pushes to
`ghcr.io/crispywaffles666/asahi-atomic-niri`, and signs with cosign.

To build locally:

```bash
podman build --platform linux/arm64 -t asahi-atomic-niri .
```

## Validation

The build fails closed on checks in `files/scripts/validate-image.sh` (required
packages present, no GNOME/KDE session, no gaming/x86 packages, Asahi hardware
packages present, referenced binaries available, distrobox arm64 manifests,
per-user flatpak bootstrap present) **and** on Asahi boot-chain hardening checks:
patched `update-m1n1` (exactly the safe `gzip -nc` invocation) **and** the
namespaced `ASAHI_ATOMIC_DTBS` override (present exactly once, applied after
config sourcing and before `DTBS` validation), the deployment-aware DTB/m1n1
helper present and executable (free of unsafe glob-first/latest-directory
logic, exporting `ASAHI_ATOMIC_DTBS` rather than plain `DTBS`), the
`asahi-atomic-niri-update-m1n1.service` unit present and enabled, the container
signature key / `registries.d` / `policy.json` present with the expected GHCR
namespace, and the update configuration never auto-rebooting (auto-apply timers
masked). It also requires `iio-sensor-proxy` and `monitor-sensor`, the
`asahi-brightnessd` binary at `/usr/sbin/asahi-brightnessd` (executable), its
unit present and enabled with an `ExecStart` binary that exists and the
panel-backlight `ConditionPathExists` gate, plus a hardware-free smoke test that
the daemon fails cleanly (non-zero exit, no hang) when no Asahi sysfs exists.
It then runs a non-destructive `gzip -nc` self-test and a
non-destructive behavioral conflict test proving that a stale config-provided
`DTBS` cannot override the deployment-aware path during an `update-m1n1`
refresh. The final authoritative gate remains `bootc container lint
--fatal-warnings`.

## Repository layout

```
.
├── .github/workflows/build.yml   # CI: build aarch64, push, sign
├── Containerfile                 # base + packages + config + boot-safety + validation
├── files/
│   ├── dnf/                          # repo files copied into the image
│   │   ├── tailscale.repo
│   │   ├── keyd.repo                  # keyd COPR
│   │   └── ublue-packages.repo       # uupd COPR
│   ├── scripts/
│   │   ├── install-overpass-nerd.sh  # fonts
│   │   ├── install-brew.sh           # stage homebrew at build time
│   │   ├── install-asahi-brightnessd.sh  # build/install pinned upstream ALS daemon
│   │   ├── patch-update-m1n1.sh      # fail-closed Atomic patch (gzip -nc + ASAHI_ATOMIC_DTBS override)
│   │   └── validate-image.sh         # build-time assertions + boot-safety checks
│   └── system/                      # copied into the image
│       ├── etc/
│       │   ├── containers/
│       │   │   ├── policy.json          # sigstoreSigned for this GHCR namespace
│       │   │   └── registries.d/…yaml   # sigstore attachments
│       │   ├── distrobox/distrobox.ini  # arm64 container presets
│       │   ├── greetd/config.toml
│       │   ├── pki/containers/…pub      # cosign public key
│       │   ├── profile.d/brew.sh
│       │   ├── skel/                    # /etc/skel dotfiles
│       │   ├── systemd/logind.conf.d/
│       │   └── uupd/config.json
│       └── usr/
│           ├── lib/
│           │   ├── systemd/
│           │   │   ├── system/
│           │   │   │   ├── asahi-atomic-niri-update-m1n1.service  # deploy-aware refresh
│           │   │   │   ├── asahi-brightnessd.service  # ALS auto-brightness daemon
│           │   │   │   ├── brew-setup.service, flathub-setup.service
│           │   │   │   └── user/config-flatpaks.service  # per-user Flatpaks
│           │   │   └── tmpfiles.d/tuigreet.conf, homebrew.conf, tailscale.conf, config-flatpaks.conf, zz-asahi-atomic-niri.conf
│           │   └── libexec/
│           │       ├── asahi-atomic-niri/update-m1n1-helper.sh  # DTB/m1n1 helper
│           │       └── asahi-niri/config-flatpaks.sh
│           └── share/glib-2.0/schemas/zz_asahi-atomic-niri.gschema.override
└── cosign.pub
```

## License

MIT.
