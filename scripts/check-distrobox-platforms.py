#!/usr/bin/env python3
"""Validate the live OCI platforms, not image-name conventions."""
import configparser
import json
from pathlib import Path
import subprocess
import sys


def inspect(image, *options):
    return json.loads(subprocess.check_output(
        ["skopeo", "inspect", *options, "docker://" + image], text=True))


def supports_platform(manifest, os_name="linux", arch="arm64"):
    return any(item.get("platform", {}).get("os") == os_name
               and item.get("platform", {}).get("architecture") == arch
               for item in manifest.get("manifests", []))


def main():
    preset = Path(__file__).resolve().parents[1] / "files/system/etc/distrobox/distrobox.ini"
    config = configparser.ConfigParser(interpolation=None)
    config.read(preset)
    if not config.sections():
        raise ValueError("no Distrobox presets found")
    for section in config.sections():
        image = config[section]["image"].strip('"')
        manifest = inspect(image, "--raw")
        if "manifests" in manifest:
            supported = supports_platform(manifest)
        else:
            metadata = inspect(image, "--config")
            supported = metadata.get("os") == "linux" and metadata.get("architecture") == "arm64"
        if not supported:
            raise ValueError(f"{section}: {image} does not publish linux/arm64")
        print(f"{section}: {image} supports linux/arm64")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
