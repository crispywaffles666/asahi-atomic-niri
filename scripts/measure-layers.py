#!/usr/bin/env python3
"""Compressed layer delta from the client's previous image, excluding config."""
import json
from pathlib import Path
import sys


def has_chunk_plan(manifest):
    # rpm-ostree checks these per-layer annotations, not layer count or labels.
    layers = manifest.get("layers", [])
    return len(layers) > 1 and all("ostree.components" in layer.get("annotations", {})
                                   for layer in layers[1:])


def measure(previous, current):
    known = {layer["digest"] for layer in previous["layers"]}
    # Clients fetch each content-addressed blob once, even if repeated.
    layers = {layer["digest"]: layer["size"] for layer in current["layers"]}
    # Count distinct reused digests too, matching the deduplicated byte sums.
    return {"layers": len(current["layers"]),
            "reused_layers": sum(digest in known for digest in layers),
            "compressed_bytes": sum(layers.values()),
            "new_compressed_bytes": sum(size for digest, size in layers.items() if digest not in known)}


if __name__ == "__main__":
    if sys.argv[1] == "--check-plan":
        sys.exit(0 if has_chunk_plan(json.loads(Path(sys.argv[2]).read_text())) else 1)
    previous = json.loads(Path(sys.argv[1]).read_text())
    for filename in sys.argv[2:]:
        current = json.loads(Path(filename).read_text())
        print(json.dumps({"manifest": filename, **measure(previous, current)}))
