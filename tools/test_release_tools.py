import tempfile
import unittest
from pathlib import Path


class ReleaseToolsTest(unittest.TestCase):
    def test_update_payload_excludes_native_runtimes_and_private_build_values(self):
        import windows_update_payload as update
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in update.BASE_PATHS:
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(b'public application')
            self.assertEqual(len(update.validate(root)), len(update.BASE_PATHS))
            (root / 'libmpv-2.dll').write_bytes(b'native')
            with self.assertRaises(ValueError):
                update.validate(root)
            (root / 'libmpv-2.dll').unlink()
            (root / 'data/app.so').write_bytes(b'private-fixture-value')
            with self.assertRaises(ValueError):
                update.validate(root, blocked_values=['private-fixture-value'])

    def test_update_payload_requires_existing_base_asset_paths(self):
        import windows_update_payload as update
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'payload'
            base = Path(folder) / 'base'
            for name in update.BASE_PATHS:
                for directory in (root, base):
                    file = directory / name
                    file.parent.mkdir(parents=True, exist_ok=True)
                    file.write_bytes(b'public application')
            update.validate(root, base=base)
            (root / 'data/new-asset').write_bytes(b'new')
            with self.assertRaises(ValueError):
                update.validate(root)
            with self.assertRaises(ValueError):
                update.validate(root, base=base)
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
