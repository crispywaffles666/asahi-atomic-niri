#!/usr/bin/bash
# Resolve once, verify that immutable digest, and give the builder that same ref.
set -euo pipefail
repository=$1
version=$2
key=$3
separator=:
[[ $version == sha256:* ]] && separator=@
manifest=$(mktemp)
trap 'rm -f "$manifest"' EXIT
skopeo inspect --raw "docker://${repository}${separator}${version}" >"$manifest"
digest="sha256:$(sha256sum "$manifest" | cut -d ' ' -f1)"
reference="${repository}@${digest}"
# Require the legacy simple-signing format: every consumer of this namespace
# (in-image containers policy, bootc, rpm-ostree) verifies that way. Reject
# OCI-referrer bundle signatures here instead of discovering it during rechunk.
cosign verify --new-bundle-format=false --key "$key" "$reference" >&2
printf '%s\n' "$reference"
