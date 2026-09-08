import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class ManifestTests(unittest.TestCase):
    def test_layers_without_component_annotations_are_not_a_plan(self):
        has_plan = module("measure-layers").has_chunk_plan
        manifest = {"layers": [{}, {"annotations": {"ostree.components": "kernel"}},
                                {"annotations": {"ostree.components": ""}}]}
        self.assertTrue(has_plan(manifest))
        del manifest["layers"][1]["annotations"]
        self.assertFalse(has_plan(manifest))
        self.assertFalse(has_plan({"layers": []}))

    def test_amd64_and_attestation_do_not_mean_arm64(self):
        supports = module("check-distrobox-platforms").supports_platform
        manifest = {"manifests": [{"platform": {"os": "linux", "architecture": "amd64"}},
                                  {"platform": {"os": "unknown", "architecture": "unknown"}}]}
        self.assertFalse(supports(manifest))
        manifest["manifests"].append({"platform": {"os": "linux", "architecture": "arm64"}})
        self.assertTrue(supports(manifest))

    def test_layer_delta_counts_new_compressed_blobs_once(self):
        measure = module("measure-layers").measure
        before = {"layers": [{"digest": "A", "size": 10}]}
        after = {"layers": [{"digest": "A", "size": 10}, {"digest": "B", "size": 25},
                            {"digest": "B", "size": 25}]}
        self.assertEqual(measure(before, after), {"layers": 3, "reused_layers": 1,
                         "compressed_bytes": 35, "new_compressed_bytes": 25})


class PublishTests(unittest.TestCase):
    def run_publish(self, failure="", branch="refs/heads/main", event="push"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidate = root / "rechunk-output/candidate.json"
            candidate.parent.mkdir()
            candidate.write_text('{"layers": []}\n')
            digest = "sha256:" + hashlib.sha256(candidate.read_bytes()).hexdigest()
            bindir = root / "bin"
            bindir.mkdir()
            for command in ("skopeo", "cosign"):
                mock = bindir / command
                mock.write_text('#!/bin/bash\n'
                                'printf "%s %s\\n" "${0##*/}" "$*" >>"$CALL_LOG"\n'
                                '[[ "$*" != "$FAIL"* || -z "$FAIL" ]] || exit 1\n'
                                'if [[ ${0##*/} == skopeo && $1 == inspect ]]; then echo "$DIGEST"; fi\n')
                mock.chmod(0o755)
            env = {**os.environ, "PATH": str(bindir) + os.pathsep + os.environ["PATH"],
                   "CALL_LOG": str(root / "calls"), "DIGEST": digest, "FAIL": failure,
                   "GITHUB_REF": branch, "GITHUB_EVENT_NAME": event, "GITHUB_RUN_ID": "123",
                   "GITHUB_RUN_ATTEMPT": "2", "GITHUB_SHA": "abc123", "FEDORA_RELEASE": "44",
                   "IMAGE_NAME": "example.com/image"}
            result = subprocess.run(["bash", str(ROOT / "scripts/publish-image.sh")], cwd=root,
                                    env=env, capture_output=True, text=True)
            calls = (root / "calls").read_text().splitlines() if (root / "calls").exists() else []
            return result, calls

    def test_promotion_after_verification_and_latest_last(self):
        result, calls = self.run_publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(":build-123-2", calls[0])
        verify = next(i for i, call in enumerate(calls) if call.startswith("cosign verify"))
        promotions = [i for i, call in enumerate(calls) if call.startswith("skopeo copy --all")]
        self.assertEqual(len(promotions), 3)
        self.assertTrue(all(i > verify for i in promotions))
        self.assertTrue(calls[promotions[-1]].endswith(":latest"))

    def test_failures_never_promote(self):
        for failure in ("copy", "sign", "verify"):
            result, calls = self.run_publish(failure)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(any(call.startswith("skopeo copy --all") for call in calls))

    def test_branch_dispatch_and_pr_cannot_publish(self):
        for branch, event in (("refs/heads/testing", "workflow_dispatch"), ("refs/heads/main", "pull_request")):
            result, calls = self.run_publish(branch=branch, event=event)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(calls, [])


class HardwarePackages(unittest.TestCase):
    def test_hardware_removal_or_version_change_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rpm = root / "rpm"
            rpm.write_text('#!/bin/bash\nprintf "%s\\n" "$PACKAGES"\n')
            rpm.chmod(0o755)
            env = {**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                   "PACKAGES": "kernel-core\t0:1-1.aarch64\nmesa-dri-drivers\t0:1-1.aarch64"}
            script = str(ROOT / "files/scripts/hardware-package-set.sh")
            before = str(root / "before")
            subprocess.run(["bash", script, "snapshot", before], env=env, check=True)
            for packages, expected in ((env["PACKAGES"] + "\nnew-desktop\t0:1-1.aarch64", 0),
                                       ("kernel-core\t0:1-1.aarch64", 1),
                                       (env["PACKAGES"].replace("mesa-dri-drivers\t0:1", "mesa-dri-drivers\t0:2"), 1)):
                result = subprocess.run(["bash", script, "check", before],
                                        env={**env, "PACKAGES": packages}, capture_output=True)
                self.assertEqual(result.returncode, expected)


if __name__ == "__main__":
    unittest.main()
