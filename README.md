# asahi-atomic-niri

A Fedora Asahi Remix Atomic (bootc) image with the **niri** compositor and
**Noctalia** shell — the same tiling Wayland desktop experience as
[crispywaffles666/bazzite-niri](https://github.com/crispywaffles666/bazzite-niri),
built for Apple Silicon M-series Macs.

**Mission:** reproduce the `bazzite-niri` desktop and workflow on an M2 Mac,
on top of a clean Fedora Asahi Remix bootable container. No Bazzite, no gaming
stack, no x86_64 assumptions.

## Login flow

```
greetd / tuigreet
  → niri (Wayland compositor)
    → Noctalia (shell: bar, launcher, notifications, lock, OSD, idle)
```

There is **no** GNOME or KDE session. Niri is the compositor and Noctalia
provides the shell. GNOME *libraries* are used selectively (portals, keyring,
Nautilus) exactly as `bazzite-niri` does.

## Architecture

### Base image

`quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44`

This is the Fedora Asahi Remix **base-atomic** bootable container, built from
the official [fedora-asahi-remix-atomic-desktops/images](https://github.com/fedora-asahi-remix-atomic-desktops/images)
project. It is chosen over Silverblue/Kinoite because:

- It ships **no desktop environment** — we add niri + Noctalia instead of
  adding them alongside GNOME/KDE and removing one afterward. This matches the
  "no GNOME or KDE desktop" goal cleanly.
- It retains the **full Asahi hardware stack**: Asahi kernel (COPR
  `@asahi/kernel`), Asahi Mesa (`@asahi/mesa`), firmware, `update-m1n1`,
  `dracut-asahi`, `alsa-ucm-asahi`, U-Boot, and the Apple build chain. None of
  that is touched.
- It already includes the infrastructure bootc systems need (`rpm-ostree`,
  `podman`, `skopeo`, `flatpak`, `xdg-desktop-portal`,
  `xdg-desktop-portal-gtk`, Xwayland).

Fedora 44 is the current supported Asahi Remix release. We derive a new
bootable container (`FROM ...base-atomic:44`) using a standard `Containerfile`,
which is the documented and simplest way to layer a desktop on top of a Fedora
Atomic base.

### Build system

A plain **Containerfile** (`podman build` / `docker buildx`) rather than
BlueBuild. Rationale:

- The Asahi Atomic images are *not* BlueBuild layers; they are stand-alone
  bootc containers published to `quay.io`. Layering our image as `FROM` the
  published Asahi `base-atomic` is the most direct, maintainable path.
- The base image is a ready bootable container, so we don't need rpm-ostree's
  treefile compose machinery — a `FROM` + `dnf install` is simpler than
  re-deriving the whole Asahi manifest.
- GitHub Actions builds natively on an `ubuntu-24.04-arm` runner (no QEMU
  emulation), pushes to `ghcr.io/crispywaffles666/asahi-atomic-niri`, and signs
  with cosign.

BlueBuild would work, but it adds a layer of generated-files indirection for no
benefit over a directly readable `Containerfile` here.

## What was ported (unchanged) from `bazzite-niri`

All of `files/system/etc/skel/` is reused verbatim where it is
architecture-independent:

- **Niri** config (`config.kdl` + `cfg/`): keybinds, layout, animations,
  window rules, autostart (noctalia, overview-autoclose, screenshot-notify,
  xwayland-satellite), gestures, misc/environment.
- **Noctalia** config (`config.toml`, `colors.json`, `notification-rules.json`,
  `plugins.json` + the full polkit-agent plugin incl. i18n).
- **Shell/terminal**: `.bashrc`, `.zshrc`, `.zshenv`, `.zsh_plugins.txt`,
  `.blerc`, starship, alacritty, ghostty, micro.
- **Applications**: geany, btop, cava (+shaders), fastfetch, satty, yazi,
  `starship.toml`.
- **Helper scripts**: `niri-overview-autoclose.sh`, `screenshot-notify.sh`,
  `smile-paste.sh`.
- **System**: greetd `config.toml` (tuigreet with Dracula theme),
  `logind.conf.d/50-idle-suspend.conf`, `tmpfiles.d/tuigreet.conf`,
  gschema override (Graphite-purple-Dark-dracula theme, Colloid-Dracula-Dark
  icons, Overpass Nerd Font).
- Fonts via `files/scripts/install-overpass-nerd.sh` (Overpass Nerd Font,
  arch-independent).

## What was adapted

| Item | Change |
|------|--------|
| Base image | Fedora Asahi `base-atomic:44` instead of `bazzite-gnome:stable` |
| Build system | Containerfile instead of BlueBuild recipe |
| Repos | Terra + Brave enabled at build time; no Bazzite repos |
| `/opt` handling | `base-atomic` ships `/opt` as a dangling symlink to a non-existent `/var/opt`, which breaks Brave's (Chrome-style) RPM cpio unpack (`File exists`). `rm -rf /opt` lets Brave own a real `/opt` as read-only composefs image content — the correct model for a browser, and keeps Bootc's `var-tmpfiles` lint clean (vs. installing into `/var/opt`, which the lint would flag). |
| fastfetch logo | Removed Bazzite-specific `/usr/share/ublue-os/bazzite/logo.txt` reference (uses default Fedora logo) |
| btop GPU list | `shown_gpus = "apple"` instead of `nvidia amd intel` |
| Validation | Extended: also checks Asahi packages present, gaming/x86 packages absent, all configured binaries exist |

## What was dropped (intentionally)

Nothing from the desktop. Dropped entirely are Bazzite's own contents that the
base now provides or that are wrong for Apple Silicon:

- Bazzite kernel / OGC kernel pieces (Asahi kernel from base is used).
- Gaming stack: Steam, Proton, Lutris, Gamescope, Wine, gaming utilities.
- NVIDIA / AMD drivers, akmods, x86_64 driver config.
- Bazzite-specific hardware services and PC hardware configuration.
- The `remove-gnome.sh` script (unneeded — no GNOME to remove).

## Packages

Installed on top of `base-atomic`:

- **Compositor/login:** `niri`, `xwayland-satellite`, `greetd`, `tuigreet`
- **Shell:** `noctalia`
- **Terminals:** `alacritty`, `ghostty` (Terra)
- **Desktop apps:** `nautilus`, `gnome-keyring`, `seahorse`,
  `xdg-desktop-portal-gnome`, `xdg-desktop-portal-gtk`, `geany`,
  `brave-browser` (Brave repo)
- **Tools:** `brightnessctl`, `playerctl`, `inotify-tools`, `wl-clipboard`,
  `wtype`, `pavucontrol`, `cava`, `satty` (Terra), `xterm`, `zsh`, `bat`,
  `micro`, `ripgrep`, `stow`, `yazi` (Terra), `starship` (Terra), `fastfetch`,
  `libnotify`, `xdg-utils`, `overpass-fonts`, `pulseaudio-utils`

> **aarch64 availability was verified** for every package. Notable: `noctalia`,
> `niri`, `alacritty`, `greetd`, `tuigreet` come from Fedora official repos
> (all aarch64). `ghostty`, `satty`, `yazi`, `starship` come from **Terra**
> (aarch64 builds confirmed). `brave-browser` comes from Brave's own RPM repo
> (aarch64 builds confirmed).

Flatpaks installed per-user at first login: `it.mijorus.smile` (emoji picker).

### GTK themes

As in `bazzite-niri`, the image ships a gschema override that selects the
`Graphite-purple-Dark-dracula` GTK theme and `Colloid-Dracula-Dark` icon
theme, plus the Overpass Nerd Font. The themes themselves are not packaged in
this image (or in Bazzite) — they are installed by the user, exactly as on a
`bazzite-niri` machine. Install them from the vinceliuice theme repos and drop
them into `~/.themes` and `~/.icons` (or `/usr/share/themes` /
`/usr/share/icons`) to complete the Dracula look.

## Installation

> **Important:** Installing on a real Mac with macOS is a *separate* problem
> from building this image. Asahi Linux handles partition layout and the
> Apple Silicon boot chain (m1n1, U-Boot). **Do not** repartition or touch the
> boot chain yourself; use the standard Asahi Linux installer to create the
> Fedora Asahi Remix system, then rebase onto this image.

Once a stock Fedora Asahi Remix (or this image) is booted, rebase to this image:

```bash
# Import the signing key (first time only)
sudo rpm-ostree rebase ostree-unverified-image:registry:ghcr.io/crispywaffles666/asahi-atomic-niri:latest
sudo reboot
```

Because the image extends the official Asahi `base-atomic`, it inherits the
Asahi boot chain, kernel, and hardware support unchanged. Rollback is standard
bootc: pick a previous deployment from the boot menu. macOS Recovery remains
untouched (Asahi installs into free space and keeps macOS intact).

## Validation

The Containerfile's final build steps validate the image twice:

- `files/scripts/validate-image.sh` fails the build if:
  - any required desktop package is missing,
  - any GNOME/KDE desktop session package is present,
  - any Bazzite/gaming or x86-only package is present,
  - any required Asahi hardware package is missing,
  - any binary referenced by Niri/Noctalia/helper scripts is unavailable.
- `bootc container lint --fatal-warnings` (the authoritative static gate)
  verifies the image is a well-formed Bootc container. Because the pristine
  `base-atomic:44` passes all lints, a derived image must too; build residue
  left by `dnf`/package scripts is cleaned so this passes without weakening it.

## Image signing

Images are signed with **cosign**. The private key is stored in the GitHub
repository secret `SIGNING_SECRET`; the public key is committed as
`cosign.pub`. CI signs the `main`-branch builds.

To verify a pulled image:

```bash
cosign verify \
  --key cosign.pub \
  ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

## Rebuilding locally

```bash
podman build --platform linux/arm64 -t asahi-atomic-niri .
```

## Repository layout

```
.
├── .github/workflows/build.yml   # CI: build aarch64, push, sign
├── Containerfile                 # base + packages + config + residue cleanup + bootc lint
├── files/
│   ├── scripts/
│   │   ├── install-overpass-nerd.sh  # fonts (arch-independent)
│   │   └── validate-image.sh         # build-time assertions
│   └── system/                      # copied into the image
│       ├── etc/
│       │   ├── greetd/config.toml
│       │   ├── skel/                # /etc/skel dotfiles (all of it)
│       │   └── systemd/logind.conf.d/
│       └── usr/
│           ├── lib/tmpfiles.d/tuigreet.conf
│           └── share/glib-2.0/schemas/zz_asahi-atomic-niri.gschema.override
└── cosign.pub
```

## License

MIT.
