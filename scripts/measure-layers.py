#!/usr/bin/env python3
"""Compressed layer delta from the client's previous image, excluding config."""
import json
from pathlib import Path
import sys


def measure(previous, current):
    known = {layer["digest"] for layer in previous["layers"]}
    # Clients fetch each content-addressed blob once, even if repeated.
    layers = {layer["digest"]: layer["size"] for layer in current["layers"]}
    return {"layers": len(current["layers"]),
            "reused_layers": sum(layer["digest"] in known for layer in current["layers"]),
            "compressed_bytes": sum(layers.values()),
            "new_compressed_bytes": sum(size for digest, size in layers.items() if digest not in known)}


if __name__ == "__main__":
    previous = json.loads(Path(sys.argv[1]).read_text())
    for filename in sys.argv[2:]:
        current = json.loads(Path(filename).read_text())
        print(json.dumps({"manifest": filename, **measure(previous, current)}))
