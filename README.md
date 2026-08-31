# asahi-atomic-niri

A Fedora Asahi Remix Atomic (bootc) image with the **niri** compositor and
**Noctalia** shell for Apple Silicon Macs (M-series) — the same tiling Wayland
desktop as [crispywaffles666/bazzite-niri](https://github.com/crispywaffles666/bazzite-niri),
built as a clean bootable container on top of Fedora Asahi Remix.

There is **no GNOME or KDE session** — niri is the compositor and Noctalia
provides the shell (bar, launcher, notifications, lock, OSD, idle). GNOME
libraries are used selectively (portals, keyring, Nautilus), as in
`bazzite-niri`.

## What's included

Built on `quay.io/fedora-asahi-remix-atomic-desktops/base-atomic:44`, which
ships no desktop environment and retains the full Asahi hardware stack (Asahi
kernel, Mesa, firmware, `update-m1n1`, `dracut-asahi`, `alsa-ucm-asahi`,
U-Boot).

**Compositor / login:** niri, xwayland-satellite, greetd, tuigreet

**Shell:** Noctalia

**Terminals:** alacritty, ghostty

**Desktop apps:** nautilus, gnome-keyring, seahorse, xdg-desktop-portal-gnome,
xdg-desktop-portal-gtk, geany, brave-browser

**Tools:** brightnessctl, playerctl, inotify-tools, wl-clipboard, wtype,
pavucontrol, cava, satty, xterm, zsh, bat, micro, ripgrep, stow, yazi,
starship, fastfetch, libnotify, xdg-utils, overpass-fonts, pulseaudio-utils

User dotfiles and configs (`/etc/skel`): niri (`config.kdl` + `cfg/`), Noctalia,
bash/zsh/starship, alacritty, ghostty, micro, geany, btop, cava, fastfetch,
satty, yazi, and the helper scripts `niri-overview-autoclose.sh`,
`screenshot-notify.sh`, and `smile-paste.sh`. The Overpass Nerd Font is
installed at build time.

Flatpaks installed per-user at first login: `it.mijorus.smile` (emoji picker).

Not included, by design: the gaming stack (Steam, Proton, Lutris, Gamescope,
Wine), NVIDIA/AMD drivers and akmods, and other Bazzite/x86-specific contents.

### GTK theme

As in `bazzite-niri`, the image ships a gschema override that selects the
`Graphite-purple-Dark-dracula` GTK theme, `Colloid-Dracula-Dark` icon theme, and
the Overpass Nerd Font. The theme and icon packages are installed by the user
(exactly as on a `bazzite-niri` machine) — drop them into `~/.themes` and
`~/.icons` (or `/usr/share/themes` and `/usr/share/icons`) to complete the look.

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
│   ├── scripts/
│   │   ├── install-overpass-nerd.sh  # fonts
│   │   └── validate-image.sh         # build-time assertions
│   └── system/                      # copied into the image
│       ├── etc/
│       │   ├── greetd/config.toml
│       │   ├── skel/                # /etc/skel dotfiles
│       │   └── systemd/logind.conf.d/
│       └── usr/
│           ├── lib/tmpfiles.d/tuigreet.conf
│           └── share/glib-2.0/schemas/zz_asahi-atomic-niri.gschema.override
└── cosign.pub
```

## License

MIT.
