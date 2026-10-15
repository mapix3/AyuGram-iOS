import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import upstream_watch


class UpstreamWatchTests(unittest.TestCase):
    state = {'telegram_version': '13.0', 'swiftgram_tag': '12.9.2-281'}

    def test_same_versions_are_not_an_update(self):
        self.assertEqual(upstream_watch.find_updates(self.state, '13.0', 'a' * 40, '12.9.2-281'), [])

    def test_new_telegram_version(self):
        updates = upstream_watch.find_updates(self.state, '13.0.1', 'b' * 40, '12.9.2-281')
        self.assertEqual([marker for marker, _ in updates], ['telegram:13.0.1'])

    def test_older_telegram_version_is_ignored(self):
        self.assertEqual(upstream_watch.find_updates(self.state, '12.9', 'c' * 40, None), [])

    def test_new_swiftgram_tag(self):
        updates = upstream_watch.find_updates(self.state, '13.0', 'a' * 40, '13.0-283')
        self.assertEqual([marker for marker, _ in updates], ['swiftgram:13.0-283'])

    def test_latest_swiftgram_tag_orders_versions_and_builds(self):
        tags = ['12.9.2-281', 'release-12.9', '13.0-282', '12.10-300', '13.0-290', '11.15-242']
        self.assertEqual(upstream_watch.latest_swiftgram_tag(tags), '13.0-290')


if __name__ == '__main__':
    unittest.main()
