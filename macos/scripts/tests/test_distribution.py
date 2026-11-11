"""Release-tool regression tests. Application tests remain in Swift Testing."""
import json
import io
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_distribution import check_signature, expected_missing_ticket
from check_dmg_layout import check_volume
from notarize_artifact import fingerprint, notarize, save


METADATA = """Authority=Developer ID Application: Example (TEAM)
TeamIdentifier=TEAM
Timestamp=Nov 3, 2026
CodeDirectory flags=0x10000(runtime)
"""
SUBMISSION_ID = "ab3c4e69-2a39-4bc1-a324-8d52f006a402"


class InstallerLayoutChecks(unittest.TestCase):
    def test_packaged_assets_and_release_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            volume = root / "volume"
            app = root / "export/hush.app"
            metadata = {"CFBundleIdentifier": "com.decentralfreedom.hush",
                        "CFBundleShortVersionString": "0.1.0",
                        "CFBundleVersion": "14", "HushReleaseSlug": "alpha.5"}
            for target in (volume / "hush.app", app):
                (target / "Contents").mkdir(parents=True)
                (target / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            background = root / "dmg-background.png"
            background.write_bytes(b"reviewed background fixture")
            (volume / ".background").mkdir()
            packaged_background = volume / ".background" / background.name
            packaged_background.write_bytes(background.read_bytes())
            (volume / "Applications").symlink_to("/Applications")
            # Reproduce the published headless image: assets exist but no layout.
            with self.assertRaisesRegex(ValueError, "Finder layout is missing"):
                check_volume(volume, background, app)
            (volume / ".DS_Store").write_bytes(b"Finder layout fixture")
            check_volume(volume, background, app)
            packaged_background.write_bytes(b"wrong background")
            with self.assertRaisesRegex(ValueError, "background"):
                check_volume(volume, background, app)
            packaged_background.write_bytes(background.read_bytes())
            (volume / "Applications").unlink()
            (volume / "Applications").symlink_to("/tmp")
            with self.assertRaisesRegex(ValueError, "Applications"):
                check_volume(volume, background, app)
            (volume / "Applications").unlink()
            (volume / "Applications").symlink_to("/Applications")
            metadata["CFBundleVersion"] = "13"
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps(metadata))
            with self.assertRaisesRegex(ValueError, "CFBundleVersion"):
                check_volume(volume, background, app)

    def test_headless_release_stops_before_packaging_or_submission(self):
        script = Path(__file__).resolve().parents[1] / "release-dmg.sh"
        result = subprocess.run(["/bin/bash", str(script), "--app", "missing.app"],
                                capture_output=True, text=True,
                                env=dict(os.environ, HUSH_DMG_HEADLESS="1", HUSH_NOTARIZE="1"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("only allowed with --local", result.stderr)


class SignatureChecks(unittest.TestCase):
    def test_valid_signature(self):
        check_signature(METADATA, {}, "TEAM", True)

    def test_rejects_debug_signature(self):
        with self.assertRaisesRegex(ValueError, "Debug"):
            check_signature(METADATA, {"com.apple.security.get-task-allow": True}, "TEAM", True)

    def test_rejects_each_signing_defect(self):
        for old, new in (("Developer ID Application", "Apple Development"),
                         ("TeamIdentifier=TEAM", "TeamIdentifier=OTHER"),
                         ("Timestamp=", "Signed Time="), ("(runtime)", "(none)")):
            with self.subTest(defect=old), self.assertRaises(ValueError):
                check_signature(METADATA.replace(old, new), {}, "TEAM", True)

    def test_dylib_does_not_require_process_runtime_flag(self):
        check_signature(METADATA.replace("(runtime)", "(none)"), {}, "TEAM", False)

    def test_only_missing_ticket_is_expected_before_submission(self):
        missing = {"SyspolicyCheckShortError": "Notary Ticket Missing"}
        def result(findings, code=70):
            return subprocess.CompletedProcess([], code, json.dumps({"output": findings}), "")
        self.assertTrue(expected_missing_ticket(result([missing])))
        for value in (result([]), result([missing], 1), result([missing, {}]),
                      result([{"SyspolicyCheckShortError": "Invalid Signature"}]),
                      subprocess.CompletedProcess([], 70, "invalid JSON", "")):
            with self.subTest(value=value):
                self.assertFalse(expected_missing_ticket(value))


class NotaryChecks(unittest.TestCase):
    def test_dmg_submission_covers_app_and_failure_stops_stapling(self):
        # Exercise the packaging entry point with a real app plist and isolated
        # command doubles. No signing identity, network or Apple account is used.
        for notary_exit in (0, 37):
            with self.subTest(notary_exit=notary_exit), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                app = root / "hush.app"
                (app / "Contents").mkdir(parents=True)
                (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                    "CFBundleShortVersionString": "0.1.0",
                    "CFBundleVersion": "13",
                    "HushReleaseSlug": "alpha.4",
                }))
                commands_path = root / "commands.jsonl"
                binaries = root / "bin"
                binaries.mkdir()
                tool_source = f"#!{sys.executable}\n" + '''import json, os, pathlib, sys
tool = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["HUSH_TEST_COMMANDS"], "a") as log:
    log.write(json.dumps([tool, *args]) + "\\n")
if tool == "create-dmg":
    pathlib.Path(args[-2]).write_bytes(b"packaging fixture")
if tool == "codesign":
    for arg in args:
        if arg.startswith("--extract-certificates="):
            pathlib.Path(arg.split("=", 1)[1] + "0").write_bytes(b"certificate fixture")
if tool == "python3" and pathlib.Path(args[0]).name == "notarize_artifact.py":
    sys.exit(int(os.environ["HUSH_TEST_NOTARY_EXIT"]))
'''
                for name in ("python3", "create-dmg", "codesign", "xcrun"):
                    tool = binaries / name
                    tool.write_text(tool_source)
                    tool.chmod(0o755)
                environment = {key: value for key, value in os.environ.items() if not key.startswith("HUSH_")}
                environment.update(PATH=f"{binaries}:{os.environ['PATH']}",
                                   HUSH_NOTARIZE="1", HUSH_TEST_NOTARY_EXIT=str(notary_exit),
                                   HUSH_TEST_COMMANDS=str(commands_path))
                output = root / "hush.dmg"
                script = Path(__file__).resolve().parents[1] / "release-dmg.sh"
                result = subprocess.run(["/bin/bash", str(script), "--app", str(app),
                                         "--output", str(output)], capture_output=True,
                                        text=True, env=environment)
                self.assertEqual(result.returncode, notary_exit, result.stderr)
                commands = [json.loads(line) for line in commands_path.read_text().splitlines()]
                submissions = [command for command in commands
                               if command[0] == "python3" and Path(command[1]).name == "notarize_artifact.py"]
                self.assertEqual([command[2:] for command in submissions], [[str(output)]])
                staples = [command for command in commands if command[:3] == ["xcrun", "stapler", "staple"]]
                if notary_exit:
                    self.assertEqual(staples, [])
                    self.assertFalse(any("postflight" in command for command in commands))
                else:
                    self.assertEqual(staples, [["xcrun", "stapler", "staple", str(app)]])
                    self.assertLess(commands.index(submissions[0]), commands.index(staples[0]))
                    self.assertIn("postflight", commands[-1])

    def test_default_build_reaches_archive_under_macos_bash(self):
        # Stop at the archive invocation; no signing, build or upload occurs.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fake_xcode = root / "xcodebuild"
            fake_xcode.write_text('#!/bin/sh\n[ "$1" != "-version" ] || exit 0\nprintf "%s\\n" "$@"\nexit 42\n')
            fake_xcode.chmod(0o755)
            environment = {key: value for key, value in os.environ.items() if not key.startswith("HUSH_")}
            environment.update(PATH=f"{root}:{os.environ['PATH']}", HUSH_RELEASE_DIRECTORY=str(root / "release"))
            script = Path(__file__).resolve().parents[1] / "build-dmg.sh"
            result = subprocess.run(["/bin/bash", str(script)], capture_output=True, text=True, env=environment)
            self.assertEqual(result.returncode, 42, result.stderr)
            self.assertIn("archive", result.stdout)
            self.assertIn("-onlyUsePackageVersionsFromResolvedFile", result.stdout)
            self.assertIn("ARCHS=arm64", result.stdout)
            self.assertNotIn("-skipMacroValidation", result.stdout)

    def test_submission_requires_explicit_opt_in(self):
        environment = dict(os.environ, HUSH_NOTARIZE="0")
        script = Path(__file__).resolve().parents[1] / "notarize_artifact.py"
        result = subprocess.run([sys.executable, str(script), "missing.app"],
                                capture_output=True, text=True, env=environment)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Submission is opt-in", result.stderr)

    def test_fingerprint_detects_resource_and_symlink_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary)
            resource = app / "resource"
            resource.write_text("original")
            before = fingerprint(app)
            resource.write_text("changed")
            self.assertNotEqual(fingerprint(app), before)
            link = app / "link"
            link.symlink_to("resource")
            before = fingerprint(app)
            link.unlink()
            link.symlink_to("elsewhere")
            self.assertNotEqual(fingerprint(app), before)

    def test_resume_never_resubmits_and_only_accepted_can_staple(self):
        for status in ("In Progress", "Invalid", "Accepted"):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                app = root / "hush.dmg"
                app.write_bytes(b"signed fixture")
                reports = root / "reports"
                reports.mkdir()
                save(reports / f"hush.dmg-{fingerprint(app)}.json", {"id": SUBMISSION_ID})
                commands = []
                def fake_run(*args, **kwargs):
                    commands.append(args)
                    body = json.dumps({"id": SUBMISSION_ID, "status": status})
                    return subprocess.CompletedProcess(args, 1 if "validate" in args else 0, body, "")
                with patch("notarize_artifact.check", return_value={}), patch("notarize_artifact.run", fake_run), patch("sys.stdout", new_callable=io.StringIO):
                    if status == "Accepted":
                        notarize(app, "profile", "TEAM", reports, SUBMISSION_ID)
                    else:
                        with self.assertRaisesRegex(RuntimeError, "Apple status"):
                            notarize(app, "profile", "TEAM", reports, SUBMISSION_ID)
                self.assertFalse(any("submit" in command for command in commands))
                self.assertEqual(any("staple" in command for command in commands), status == "Accepted")


@unittest.skipUnless(os.environ.get("HUSH_DISTRIBUTION_TEST_APP"), "requires an exported app")
class ExportedBundleChecks(unittest.TestCase):
    def test_modified_resource_invalidates_actual_export(self):
        original = Path(os.environ["HUSH_DISTRIBUTION_TEST_APP"])
        script = Path(__file__).resolve().parents[1] / "check_distribution.py"
        with tempfile.TemporaryDirectory(prefix="hush-seal-test-") as temporary:
            candidate = Path(temporary) / "hush.app"
            subprocess.run(["/usr/bin/ditto", str(original), str(candidate)], check=True)
            # Bundle resources are covered by the outer signature seal.
            with (candidate / "Contents/Info.plist").open("ab") as target:
                target.write(b"\n<!-- modified after export -->\n")
            result = subprocess.run([sys.executable, str(script), str(candidate)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("codesign --verify", result.stdout)


if __name__ == "__main__":
    unittest.main()
