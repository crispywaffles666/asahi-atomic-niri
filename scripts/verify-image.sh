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
cosign verify --key "$key" "$reference" >&2
printf '%s\n' "$reference"
