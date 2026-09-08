"""Exercise the real OCI transport with rpm-ostree's untagged layout shape."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


class OciLayout(unittest.TestCase):
    def test_single_untagged_descriptor_is_readable_without_latest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            blobs = root / "blobs/sha256"
            blobs.mkdir(parents=True)

            def blob(value, media_type):
                data = json.dumps(value).encode()
                digest = hashlib.sha256(data).hexdigest()
                (blobs / digest).write_bytes(data)
                return {"mediaType": media_type, "digest": "sha256:" + digest, "size": len(data)}

            config = blob({"architecture": "arm64", "os": "linux", "config": {},
                           "rootfs": {"type": "layers", "diff_ids": []}},
                          "application/vnd.oci.image.config.v1+json")
            manifest = {"schemaVersion": 2, "config": config, "layers": []}
            descriptor = blob(manifest, "application/vnd.oci.image.manifest.v1+json")
            (root / "oci-layout").write_text('{"imageLayoutVersion":"1.0.0"}')
            (root / "index.json").write_text(json.dumps({"schemaVersion": 2, "manifests": [descriptor]}))
            output = subprocess.check_output(["skopeo", "inspect", "--raw", "oci:" + directory], text=True)
            self.assertEqual(json.loads(output), manifest)
            tagged = subprocess.run(["skopeo", "inspect", "--raw", "oci:" + directory + ":latest"],
                                    capture_output=True)
            self.assertNotEqual(tagged.returncode, 0)


if __name__ == "__main__":
    unittest.main()
