import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('ayugram_ci', Path(__file__).resolve().parents[1] / 'ayugram_ci.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.env = dict(TELEGRAM_API_ID='12345', TELEGRAM_API_HASH='a' * 32,
                        APPLE_TEAM_ID='ABCDE12345', APP_BUNDLE_ID='org.example.ayu')

    def test_preserves_required_swiftgram_configuration_types(self):
        config = ci.build_configuration(self.env)
        self.assertEqual(config['api_id'], '12345')
        self.assertIs(config['enable_siri'], False)
        self.assertIs(config['enable_icloud'], False)
        self.assertEqual(config['sg_config'], '')
        self.assertEqual(config['is_internal_build'], 'true')

    def test_missing_secrets_fail_without_echoing_values(self):
        del self.env['APPLE_TEAM_ID']
        with self.assertRaisesRegex(ValueError, 'APPLE_TEAM_ID') as error:
            ci.build_configuration(self.env)
        self.assertNotIn(self.env['TELEGRAM_API_HASH'], str(error.exception))

    def test_rejects_starlark_injection_into_upstream_variables(self):
        for key in self.env:
            with self.subTest(key=key):
                bad = dict(self.env, **{key: 'bad"\nload("evil")'})
                with self.assertRaisesRegex(ValueError, key):
                    ci.build_configuration(bad)

    def test_rejects_out_of_range_api_id(self):
        self.env['TELEGRAM_API_ID'] = '9999999999'
        with self.assertRaises(ValueError):
            ci.build_configuration(self.env)


class ArtifactTests(unittest.TestCase):
    def make_ipa(self, root, platform='iPhoneOS', executable=True):
        path = root / 'test.ipa'
        plist = dict(CFBundleIdentifier='org.example.ayu', CFBundleExecutable='Swiftgram',
                     CFBundleSupportedPlatforms=[platform])
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('Payload/Swiftgram.app/Info.plist', plistlib.dumps(plist))
            if executable:
                archive.writestr('Payload/Swiftgram.app/Swiftgram', b'test executable')
        return path

    def test_device_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            info = ci.verify_ipa(self.make_ipa(Path(tmp)), 'org.example.ayu')
            self.assertEqual(info['CFBundleSupportedPlatforms'], ['iPhoneOS'])

    def test_simulator_is_not_an_ipa_deliverable(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'device build'):
                ci.verify_ipa(self.make_ipa(Path(tmp), platform='iPhoneSimulator'), 'org.example.ayu')

    def test_missing_executable(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'executable'):
                ci.verify_ipa(self.make_ipa(Path(tmp), executable=False), 'org.example.ayu')

    def test_wrong_application(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'bundle identifier'):
                ci.verify_ipa(self.make_ipa(Path(tmp)), 'org.other.app')

    def test_cleanup_removes_only_generated_credentials(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = root / 'build-input/ayugram-ci-configuration.json'
            variables = root / 'build-input/configuration-repository/variables.bzl'
            variables.parent.mkdir(parents=True)
            config.write_text('temporary secret')
            variables.write_text('temporary secret')
            keep = root / 'user-configuration.json'
            keep.write_text('keep')
            ci.cleanup(root)
            self.assertFalse(config.exists())
            self.assertFalse(variables.exists())
            self.assertTrue(keep.exists())


if __name__ == '__main__':
    unittest.main()
