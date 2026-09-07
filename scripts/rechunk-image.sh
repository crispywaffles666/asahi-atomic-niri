#!/usr/bin/bash
set -euo pipefail
: "${RAW_IMAGE:?}" "${CHUNKED_IMAGE:?}"
mkdir -p rechunk-output
graphroot=$(podman info --format '{{.Store.GraphRoot}}')

rechunk() {
    local name=$1 target=$2 previous=${3:-} start=$SECONDS
    local opts=()
    [[ -z $previous ]] || opts+=(--previous-build "docker://$previous")
    podman run --rm --pull=never --privileged \
        --mount="type=image,src=$RAW_IMAGE,target=/rpm-ostree" \
        --mount="type=bind,src=$graphroot,target=/run/host-container-storage,rw" \
        --mount=type=tmpfs,target=/run/rpm-ostree-storage \
        --entrypoint /usr/bin/rpm-ostree "$RAW_IMAGE" \
        compose build-chunked-oci --max-layers 127 --format-version=2 --bootc \
        --rootfs /rpm-ostree "${opts[@]}" \
        --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]$target"
    printf '%s rechunk seconds: %s\n' "$name" "$((SECONDS - start))" | tee -a rechunk-output/timing.txt
    # Measure the same compressed OCI manifest that publishing copies unchanged.
    podman push --format oci --compression-format gzip "$target" "oci:rechunk-output/$name:latest"
    skopeo inspect --raw "oci:rechunk-output/$name:latest" >"rechunk-output/$name.json"
}

rechunk candidate "$CHUNKED_IMAGE" "${PREVIOUS_IMAGE:-}"
if [[ -n ${PREVIOUS_IMAGE:-} ]]; then
    skopeo inspect --raw "docker://$PREVIOUS_IMAGE" >rechunk-output/previous.json
    manifests=(rechunk-output/candidate.json)
    if [[ ${BENCHMARK_RECHUNK:-false} == true ]]; then
        rechunk fresh localhost/asahi-atomic-niri:fresh-plan
        manifests+=(rechunk-output/fresh.json)
    fi
    python3 scripts/measure-layers.py rechunk-output/previous.json "${manifests[@]}" | tee rechunk-output/measurements.jsonl
else
    echo 'First build: no previous manifest to measure against.' >rechunk-output/measurements.jsonl
fi
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    {
        printf '\n### Rechunk comparison\n\nCompressed layer bytes (not installed size); both plans use the same rootfs.\n\n```text\n'
        cat rechunk-output/timing.txt rechunk-output/measurements.jsonl
        printf '```\n'
    } >>"$GITHUB_STEP_SUMMARY"
fi
