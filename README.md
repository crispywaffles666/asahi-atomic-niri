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

User dotfiles and configs (`/etc/skel`): niri (`config.kdl` + `cfg/`), Noctalia,
bash/zsh/starship, alacritty, ghostty, micro, geany, btop, cava, fastfetch,
satty, yazi, and the helper scripts `niri-overview-autoclose.sh`,
`screenshot-notify.sh`, and `smile-paste.sh`.

Flatpaks installed per-user at first login: `it.mijorus.smile` (emoji picker).

## Homebrew, Tailscale, and automatic updates

Three convenience features are layered on top of the base:

- **Homebrew** — staged image-owned at build time and copied into
  `/var/home/linuxbrew` on first boot by `brew-setup.service`. Managed as the
  default user (UID 1000); brew analytics are disabled.
- **Tailscale** — installed from Tailscale's official RPM repository with
  `tailscaled.service` enabled. Run `sudo tailscale up` to join your tailnet.
- **Automatic updates** — `uupd` (from the Universal Blue `ublue-os/packages`
  COPR) runs daily via `uupd.timer` and updates the OS via bootc, flatpaks (a
  system Flathub remote is added on first boot by `flathub-setup.service`), and
  brew packages. Config lives at `/etc/uupd/config.json`.

Homebrew, tailscale, and the flathub system remote assume the machine's primary
user is UID 1000 (the Fedora/Asahi default).

## Image signing

Images are signed with **cosign**. The private key is stored in the GitHub
repository secret `SIGNING_SECRET`; the matching public key is committed as
`cosign.pub`. CI signs `main`-branch builds.

Verify a pulled image:

```bash
cosign verify \
  --key cosign.pub \
  ghcr.io/crispywaffles666/asahi-atomic-niri:latest
```

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
packages present, referenced binaries available) and on
`bootc container lint --fatal-warnings`.

## Repository layout

```
.
├── .github/workflows/build.yml   # CI: build aarch64, push, sign
├── Containerfile                 # base + packages + config + validation
├── files/
│   ├── dnf/                          # repo files copied into the image
│   │   ├── tailscale.repo
│   │   └── ublue-packages.repo       # uupd COPR
│   ├── scripts/
│   │   ├── install-overpass-nerd.sh  # fonts
│   │   ├── install-brew.sh           # stage homebrew at build time
│   │   └── validate-image.sh         # build-time assertions
│   └── system/                      # copied into the image
│       ├── etc/
│       │   ├── greetd/config.toml
│       │   ├── profile.d/brew.sh
│       │   ├── skel/                # /etc/skel dotfiles
│       │   ├── systemd/logind.conf.d/
│       │   └── uupd/config.json
│       └── usr/
│           ├── lib/
│           │   ├── systemd/system/brew-setup.service, flathub-setup.service
│           │   └── tmpfiles.d/tuigreet.conf, homebrew.conf, tailscale.conf
│           └── share/glib-2.0/schemas/zz_asahi-atomic-niri.gschema.override
└── cosign.pub
```

## License

MIT.
