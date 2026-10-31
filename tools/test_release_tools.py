import tempfile
import unittest
from pathlib import Path


class ReleaseToolsTest(unittest.TestCase):
    def test_manifest_detects_tampering_and_unsafe_paths(self):
        import release_integrity as integrity
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'app.apk').write_bytes(b'apk')
            integrity.create(root)
            integrity.verify(root)
            (root / 'app.apk').write_bytes(b'changed')
            with self.assertRaises(ValueError):
                integrity.verify(root)
            (root / 'SHA256SUMS').write_text('a' * 64 + '  ../escape\n')
            with self.assertRaises(ValueError):
                integrity.verify(root)

    def test_scanner_reports_rule_without_secret(self):
        import scan_secrets
        token = 'ghp_' + 'A' * 36
        findings = scan_secrets.inspect('example.txt', ('token=' + token).encode())
        self.assertEqual(len(findings), 1)
        self.assertNotIn(token, str(findings))
        self.assertEqual(scan_secrets.inspect('ordinary.dart', b'const x = 42;'), [])


if __name__ == '__main__':
    unittest.main()
