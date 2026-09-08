# Upstream trust roots

These keys are deliberately vendored: CI must not download a new trust root
alongside the image it is supposed to authenticate. Review key rotations.

- `ublue-os.pub`: https://github.com/ublue-os/main/blob/main/cosign.pub
- `fedora-asahi.pub`: https://github.com/fedora-asahi-remix-atomic-desktops/images/blob/main/quay.io-fedora-asahi-atomic-remix.pub
