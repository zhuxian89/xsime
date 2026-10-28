import importlib.util
import plistlib
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    'trollstore_ipa', Path(__file__).with_name('create-ios-trollstore-ipa.py'))
PACK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACK)


class TrollStoreIPATests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.app = self.root / 'RIMES.app'
        for relative, identifier in (('', PACK.VERIFY['APP_ID']),
                                     ('PlugIns/RIMESKeyboard.appex', PACK.VERIFY['KEYBOARD_ID'])):
            bundle = self.app / relative
            bundle.mkdir(parents=True)
            info = {'CFBundleIdentifier': identifier, 'CFBundleExecutable': 'Executable',
                    'CFBundleShortVersionString': '1.2.0', 'CFBundleVersion': '67',
                    'RIMESKeychainGroup': PACK.VERIFY['KEYCHAIN_GROUP'],
                    'RIMESAppGroup': PACK.VERIFY['APP_GROUP']}
            (bundle / 'Info.plist').write_bytes(plistlib.dumps(info))
            (bundle / 'Executable').write_bytes(b'fixture')
            (bundle / 'PrivacyInfo.xcprivacy').write_bytes(plistlib.dumps({}))

    def test_app_and_extension_receive_same_concrete_shared_groups(self):
        targets = PACK.bundles(self.app)
        self.assertEqual(targets[0][0].suffix, '.appex')
        rights = [PACK.entitlements(info) for _, info in targets]
        for key in ('keychain-access-groups', 'com.apple.security.application-groups'):
            self.assertEqual(rights[0][key], rights[1][key])
        self.assertNotEqual(rights[0]['application-identifier'], rights[1]['application-identifier'])
        self.assertEqual(rights[0]['keychain-access-groups'], [PACK.VERIFY['KEYCHAIN_GROUP']])
        self.assertNotIn('get-task-allow', rights[0])

    def test_old_unprefixed_runtime_group_cannot_be_masked_by_signing(self):
        path = self.app / 'Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['RIMESKeychainGroup'] = 'org.scholay.rimes.ios.shared'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'Keychain group'):
            PACK.bundles(self.app)

    def test_mismatched_extension_version_is_rejected(self):
        path = self.app / 'PlugIns/RIMESKeyboard.appex/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundleVersion'] = '64'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'versions differ'):
            PACK.bundles(self.app)

    def test_unhandled_nested_code_is_rejected(self):
        (self.app / 'Extra.framework').mkdir()
        with self.assertRaisesRegex(ValueError, 'nested code'):
            PACK.bundles(self.app)

    def test_invalid_digest_fails_before_extracting_or_creating_output(self):
        source = self.root / 'input.ipa'
        source.write_bytes(b'not a zip')
        output = self.root / 'output' / 'result.ipa'
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            PACK.package(source, output, '0' * 64)
        self.assertFalse(output.parent.exists())

    def test_archive_rejects_traversal_and_symlinks(self):
        for name, mode in (('Payload/../../escape', 0), ('/Payload/file', 0),
                           ('Payload/link', stat.S_IFLNK | 0o777)):
            with self.subTest(name=name):
                ipa = self.root / 'bad.ipa'
                with zipfile.ZipFile(ipa, 'w') as archive:
                    entry = zipfile.ZipInfo(name)
                    entry.external_attr = mode << 16
                    archive.writestr(entry, 'target')
                with self.assertRaises(ValueError):
                    PACK.validate_zip(ipa)

    def test_official_ditto_metadata_is_accepted(self):
        ipa = self.root / 'official.ipa'
        with zipfile.ZipFile(ipa, 'w') as archive:
            archive.writestr('Payload/RIMES.app/Info.plist', b'fixture')
            archive.writestr('__MACOSX/', b'')
            archive.writestr('__MACOSX/Payload/._RIMES.app', b'finder metadata')
        PACK.validate_zip(ipa)


if __name__ == '__main__':
    unittest.main()
