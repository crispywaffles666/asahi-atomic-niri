#!/usr/bin/bash
set -euo pipefail
: "${RAW_IMAGE:?}" "${CHUNKED_IMAGE:?}"
mkdir -p rechunk-output
output_dir="$PWD/rechunk-output"

has_plan() {
    python3 scripts/measure-layers.py --check-plan "$1"
}

rechunk() {
    local name=$1 previous=${2:-} start=$SECONDS
    local opts=()
    [[ -z $previous ]] || opts+=(--previous-build "$previous")
    podman run --rm --pull=never --privileged \
        --mount="type=image,src=$RAW_IMAGE,target=/rpm-ostree" \
        --mount="type=bind,src=$output_dir,target=/output,rw" \
        --entrypoint /usr/bin/rpm-ostree "$RAW_IMAGE" \
        compose build-chunked-oci --max-layers 127 --format-version=2 --bootc \
        --rootfs /rpm-ostree "${opts[@]}" \
        --output "oci:/output/$name"
    printf '%s rechunk seconds: %s\n' "$name" "$((SECONDS - start))" | tee -a rechunk-output/timing.txt
    # Keep the authoritative OCI layout. A containers-storage -> podman push
    # round trip discarded ostree.components, making future plans unusable.
    # Direct OCI export also avoids unpacking and recompressing before publish.
    skopeo inspect --raw "oci:rechunk-output/$name:latest" >"rechunk-output/$name.json"
    has_plan "rechunk-output/$name.json" || {
        echo 'ERROR: exported image lost its reusable chunk plan' >&2
        exit 1
    }
}

previous_plan=
if [[ -n ${PREVIOUS_IMAGE:-} ]]; then
    skopeo inspect --raw "docker://$PREVIOUS_IMAGE" >rechunk-output/previous.json
    if has_plan rechunk-output/previous.json; then
        previous_plan="docker://$PREVIOUS_IMAGE"
    fi
fi
if [[ -n $previous_plan ]]; then
    echo 'Using verified previous-image chunk plan.' | tee rechunk-output/baseline.txt
else
    echo 'No usable previous chunk plan (first build or legacy image missing ostree.components).' | tee rechunk-output/baseline.txt
fi

rechunk candidate "$previous_plan"
manifests=(rechunk-output/candidate.json)
if [[ ${BENCHMARK_RECHUNK:-false} == true ]]; then
    if [[ -n $previous_plan ]]; then
        rechunk fresh
        manifests+=(rechunk-output/fresh.json)
    else
        # Legacy published images cannot supply a valid before/after benchmark.
        # Prove the newly preserved plan can be consumed, without claiming an
        # update saving from a same-rootfs round trip.
        rechunk roundtrip oci:/output/candidate:latest
        python3 scripts/measure-layers.py rechunk-output/candidate.json \
            rechunk-output/roundtrip.json | tee rechunk-output/roundtrip.jsonl
    fi
fi
if [[ -n ${PREVIOUS_IMAGE:-} ]]; then
    python3 scripts/measure-layers.py rechunk-output/previous.json "${manifests[@]}" | tee rechunk-output/measurements.jsonl
else
    echo 'First build: no previous manifest to measure against.' >rechunk-output/measurements.jsonl
fi

# Import a disposable copy only for linting; publishing reads the original OCI
# layout, never the copy reconstructed by the container runtime.
candidate_id=$(podman pull --quiet oci:rechunk-output/candidate:latest)
podman tag "$candidate_id" "$CHUNKED_IMAGE"

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    {
        printf '\n### Rechunk comparison\n\nCompressed layer bytes (not installed size).\n\n```text\n'
        cat rechunk-output/baseline.txt rechunk-output/timing.txt rechunk-output/measurements.jsonl
        if [[ -f rechunk-output/roundtrip.jsonl ]]; then
            printf 'Same-rootfs plan smoke test (NOT an update-saving measurement):\n'
            cat rechunk-output/roundtrip.jsonl
        fi
        printf '```\n'
    } >>"$GITHUB_STEP_SUMMARY"
fi
