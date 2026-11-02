import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ayugram_origin import SEAL_PATH, open_seal, origin_payload, prepare_origin, seal, signature

ROOT = Path(__file__).resolve().parents[2]
ENV = {'GITHUB_REPOSITORY': 'mapix3/AyuGram-iOS', 'GITHUB_SHA': 'd2abe71e6863e3be2ba22adfa4ba6ee24157d512', 'GITHUB_RUN_ID': '41384897111'}


class OriginTests(unittest.TestCase):
    def test_seal_round_trip(self):
        payload = origin_payload(208301, 'custom', 'org.example.app', ENV)
        data = seal(payload, bytes(range(16)))
        self.assertEqual(open_seal(data), payload)
        self.assertEqual(payload['r'], 'mapix3/AyuGram-iOS')
        self.assertEqual(payload['c'], 'd2abe71e6863')
        self.assertEqual(payload['i'], signature('org.example.app'))
        self.assertNotIn(b'AyuGram', data)
        self.assertNotIn(b'org.example', data)

    def test_swift_vector(self):
        data = seal(origin_payload(208301, 'custom', 'org.example.app', ENV), bytes(range(16)))
        tests = (ROOT / 'ci/tests/AyuGramSecurityTests.swift').read_text(encoding='utf-8')
        self.assertIn('[' + ', '.join(str(byte) for byte in data) + ']', tests)

    def test_bad_values_are_dropped(self):
        payload = origin_payload(1, 'standard', '', {'GITHUB_REPOSITORY': 'a b', 'GITHUB_SHA': 'zz', 'GITHUB_RUN_ID': '1x'})
        self.assertEqual((payload['r'], payload['c'], payload['u'], payload['i']), ('', '', '', ''))

    def test_where_it_was_built(self):
        github = origin_payload(1, 'standard', '', ENV)
        self.assertEqual((github['p'], github['h']), ('github', 'https://github.com'))
        gitlab = origin_payload(1, 'standard', '', {'GITLAB_CI': 'true', 'CI_SERVER_URL': 'https://gitlab.com', 'CI_PROJECT_PATH': 'group/sub/ayu', 'CI_COMMIT_SHA': 'abcdef1234567', 'CI_PIPELINE_ID': '77'})
        self.assertEqual((gitlab['p'], gitlab['h'], gitlab['r'], gitlab['c'], gitlab['u']), ('gitlab', 'https://gitlab.com', 'group/sub/ayu', 'abcdef123456', '77'))
        self.assertEqual(origin_payload(1, 'standard', '', {'CM_BUILD_ID': 'x', 'CM_COMMIT': 'abcdef1'})['p'], 'codemagic')
        self.assertEqual(origin_payload(1, 'standard', '', {'BITRISE_IO': 'true'})['p'], 'bitrise')
        self.assertEqual(origin_payload(1, 'standard', '', {'CI': 'true'})['p'], 'ci')
        local = origin_payload(1, 'standard', '', {})
        self.assertEqual((local['p'], local['h'], local['r']), ('local', '', ''))
        forged = origin_payload(1, 'standard', '', {'GITHUB_REPOSITORY': 'a/b', 'GITHUB_SERVER_URL': 'javascript:alert(1)'})
        self.assertEqual(forged['h'], '', 'Only https servers are kept')

    def test_prepare_replaces_the_committed_seal(self):
        original = (ROOT / SEAL_PATH).read_text(encoding='utf-8')
        self.assertIn('private let ayuGramSeal: [UInt8] = []\n', original)
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / SEAL_PATH
            target.parent.mkdir(parents=True)
            target.write_text(original, encoding='utf-8')
            data = prepare_origin(Path(folder), 208301, 'standard', 'org.example.app', ENV)
            updated = target.read_text(encoding='utf-8')
            self.assertIn('private let ayuGramSeal: [UInt8] = [' + ', '.join(str(byte) for byte in data) + ']\n', updated)
            self.assertEqual(updated.count('ayuGramSeal: [UInt8]'), 1)
            self.assertEqual(open_seal(data)['b'], 208301)
            prepare_origin(Path(folder), 208302, 'standard', 'org.example.app', ENV)
            self.assertEqual(target.read_text(encoding='utf-8').count('ayuGramSeal: [UInt8]'), 1)
            target.write_text('nothing', encoding='utf-8')
            with self.assertRaises(ValueError):
                prepare_origin(Path(folder), 1, 'standard', '', ENV)


if __name__ == '__main__':
    unittest.main()
