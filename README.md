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

## Asahi Atomic installation / boot safety

> ⚠️ This image is **experimental** and built on top of **unofficial Fedora
> Asahi Remix Atomic** images. It is **not** endorsed or supported by the Fedora
> Asahi Remix project or the Asahi Linux project. The Asahi boot chain (m1n1,
> U-Boot, device trees) is not atomically switchable the way the OS rootfs is;
> a broken `boot.bin` can leave a Mac unbootable until recovered from macOS or
> the Asahi recovery. Treat first installs as risky, keep a known-good ESP
> backup, and do not rely on this working.

**Recommended installation route** — start from a *working* Fedora Asahi
installation rather than replacing an arbitrary root, so the ESP, m1n1, and
partitioning are already set up correctly:

```text
Fedora Asahi Minimal
→ Fedora Asahi Atomic
→ asahi-atomic-niri (this image)
```

Install/`bootc` yourself into the running Asahi Atomic system. This image keeps
the stock Fedora Asahi kernel, Mesa, firmware, U-Boot, and hardware stack — it
only adds a desktop and, importantly, a **deployment-aware m1n1/U-Boot/DTB
refresh** mechanism (below).

**First custom-image rebase (needs the unverified transport once).** Before your
system has this image's signature policy in `/etc`, the signed transport cannot
verify. Bootstrap with the unverified registry transport:

```sh
sudo rpm-ostree rebase ostree-unverified-registry:ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

`sudo systemctl reboot`

After rebooting into an image that now contains its own signature policy, switch
to the signed transport so all future updates are enforced:

```sh
sudo rpm-ostree rebase ostree-image-signed:docker://ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

`sudo systemctl reboot`

(These transport strings are valid for Fedora 44: `ostree-unverified-registry:`
pulls with HTTPS-only integrity, and `ostree-image-signed:docker://` verifies
the container image against `/etc/containers/policy.json`, which ships the
cosign public key for this GHCR namespace.)

**Updates never reboot automatically.** `uupd` stages OS updates via
bootc/rpm-ostree but does not reboot; the auto-apply/reboot timers
(`bootc-fetch-apply-updates.timer`, `rpm-ostreed-automatic.timer`) are masked.
You reboot manually to apply a staged deployment.

**After rebooting into a new deployment, the m1n1 refresh runs once.** The
oneshot service `asahi-atomic-niri-update-m1n1.service` runs after the new
deployment boots to `multi-user.target`. It:

1. resolves the *currently booted* deployment's device trees
   (`/usr/lib/modules/$(uname -r)/dtb`, i.e. the booted deployment's own `/usr`),
   never a stale `/boot/dtb` (a legacy Fedora ARM symlink — `grubby` is excluded
   from this Atomic base) and never a lexicographically-newest scan;
2. passes that deployment-aware DTB directory to `update-m1n1` through the
   namespaced `ASAHI_ATOMIC_DTBS` override. The patched `update-m1n1` applies
   this override *after* Fedora's normal `update-m1n1` configuration (e.g.
   `/etc/sysconfig/update-m1n1`) is sourced, so persistent `/etc` state that sets
   `DTBS` cannot silently replace the deployment-aware DTBs. (This is a
   hardening behavior of this image's patched copy; it is *not* official Fedora
   Asahi behavior.)
3. verifies it has the safe `gzip -nc` invocation (the fix for
   [asahi-scripts#71](https://github.com/AsahiLinux/asahi-scripts/issues/71));
4. runs `update-m1n1` to rewrite the stage-2 payload
   (`<ESP>/m1n1/boot.bin`) for that exact deployment;
5. records success for that deployment under `/var/lib/asahi-atomic-niri/`,
   so it does **not** rerun on every boot and does **not** run for a deployment
   that already refreshed;
6. **fails closed** — if `update-m1n1` fails, the deployment is *not* marked
   done and the service reports failure.

**Another reboot may be required.** The refresh updates `boot.bin` on the ESP;
that payload is what m1n1 stage-1 actually boots on the *next* boot. So after an
OS update you typically need **two** reboots: one to boot the new deployment
(which triggers the refresh), then one to make the freshly-written m1n1/U-Boot
payload take effect.

**Inspecting status:**

```sh
bootc status
systemctl status asahi-atomic-niri-update-m1n1.service
journalctl -u asahi-atomic-niri-update-m1n1.service
```

The helper also has a non-destructive `check` (no ESP writes):

```sh
sudo /usr/libexec/asahi-atomic-niri/update-m1n1-helper.sh check
```

**Rollback.** Because the OS and the ESP payload update independently, roll back
in this order:

```sh
# 1) See what you are on and what is staged.
bootc status

# 2) Roll back the OS deployment (stages the previous image; reboot to apply).
sudo bootc rollback
sudo systemctl reboot

# 3) If the new m1n1/U-Boot/DTB payload is causing boot problems, restore the
#    OS first, then mount the ESP (e.g. `sudo mount /dev/<esp> /mnt`) and
#    restore a previous `boot.bin` from the `.old` backup that update-m1n1
#    keeps at `<ESP>/m1n1/boot.bin.old`.
```

Recovery expectations: the ESP and the OS are separate; if the OS fails to boot,
the ESP payload (previous m1n1) is still intact and you can boot the previous
deployment or use macOS/Asahi recovery to restore `boot.bin`. Always keep a
`boot.bin` backup before experimenting.

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
masked). It then runs a non-destructive `gzip -nc` self-test and a
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
