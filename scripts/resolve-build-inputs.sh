#!/usr/bin/bash
set -euo pipefail
release=$(sed -n 's/^ARG FEDORA_RELEASE=//p' Containerfile)
[[ $release =~ ^[0-9]+$ ]]
base=$(bash scripts/verify-image.sh quay.io/fedora-asahi-remix-atomic-desktops/base-atomic "$release" keys/fedora-asahi.pub)
brew_arg=$(sed -n 's/^ARG BREW_IMAGE=//p' Containerfile)
brew=$(bash scripts/verify-image.sh ghcr.io/ublue-os/brew "${brew_arg##*@}" keys/ublue-os.pub)

# Fedora's disposable builder is resolved by digest; it does not use the
# Universal Blue/Asahi cosign keys. RPM signature checking remains enabled.
builder_repo=registry.fedoraproject.org/fedora
builder_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${builder_repo}:${release}")
builder="${builder_repo}@${builder_digest}"

# Use only a verified prior image as the plan/measurement baseline. Network or
# authentication failures must not silently turn a daily build into a bootstrap.
previous=
error_file=$(mktemp)
trap 'rm -f "$error_file"' EXIT
if previous_digest=$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE_NAME}:latest" 2>"$error_file"); then
    previous=$(bash scripts/verify-image.sh "$IMAGE_NAME" "$previous_digest" cosign.pub)
elif ! grep -Eqi 'manifest unknown|name unknown' "$error_file"; then
    cat "$error_file" >&2
    exit 1
fi
printf 'release=%s\nbase=%s\nbrew=%s\nbuilder=%s\nprevious=%s\n' \
    "$release" "$base" "$brew" "$builder" "$previous" >>"$GITHUB_OUTPUT"
{
    printf '### Resolved build inputs\n\n'
    printf -- '- Base (signature verified): `%s`\n' "$base"
    printf -- '- Brew (signature verified): `%s`\n' "$brew"
    printf -- '- Disposable Fedora builder: `%s`\n' "$builder"
    printf -- '- Previous signed image: `%s`\n' "${previous:-none (first build)}"
} >>"$GITHUB_STEP_SUMMARY"
