import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import check_log_privacy  # noqa: E402


class LogPrivacyTests(unittest.TestCase):
    def check(self, source: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory, "Sample.swift")
            path.write_text(source, encoding="utf-8")
            return check_log_privacy.violations(path)

    def test_public_transcript_is_refused(self):
        self.assertEqual(len(self.check('log.info("ok: \\(raw, privacy: .public)")')), 1)
        self.assertEqual(len(self.check('log.info("\\(request.text, privacy: .public)")')), 1)

    def test_private_text_and_public_metadata_pass(self):
        self.assertEqual(self.check('log.info("ok: \\(raw)")'), [])
        self.assertEqual(self.check('log.info("\\(raw.count) characters")'), [])
        self.assertEqual(self.check('log.info("\\(modelID, privacy: .public)")'), [])

    def test_print_only_inside_debug(self):
        self.assertEqual(len(self.check('print("reply: \\(raw)")')), 1)
        self.assertEqual(self.check('#if DEBUG\nprint("reply: \\(raw)")\n#endif'), [])
        self.assertEqual(len(self.check('#if DEBUG\n#endif\nNSLog("\\(raw)")')), 1)


if __name__ == "__main__":
    unittest.main()
