#!/usr/bin/bash
# No mutable user-facing alias is updated until its digest has been verified.
set -euo pipefail
[[ ${GITHUB_REF:-} == refs/heads/main && ${GITHUB_EVENT_NAME:-} != pull_request ]] \
    || { echo 'Publishing is restricted to main' >&2; exit 1; }
: "${IMAGE_NAME:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${GITHUB_SHA:?}" "${FEDORA_RELEASE:?}"
build_tag="build-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
digest="sha256:$(sha256sum rechunk-output/candidate.json | cut -d ' ' -f1)"
reference="$IMAGE_NAME@$digest"
skopeo copy --preserve-digests oci:rechunk-output/candidate:latest "docker://$IMAGE_NAME:$build_tag"
[[ $(skopeo inspect --format '{{.Digest}}' "docker://$IMAGE_NAME:$build_tag") == "$digest" ]]
cosign sign --key env://COSIGN_PRIVATE_KEY --yes "$reference"
cosign verify --key cosign.pub "$reference"

# Latest is last. Automatic workflow cancellation is disabled on main. Manual
# cancellation is still possible, but can only leave aliases on signed digests.
for tag in "${FEDORA_RELEASE}-$(date -u +%Y%m%d)" "$GITHUB_SHA" latest; do
    skopeo copy --all --preserve-digests "docker://$reference" "docker://$IMAGE_NAME:$tag"
    [[ $(skopeo inspect --format '{{.Digest}}' "docker://$IMAGE_NAME:$tag") == "$digest" ]]
done
