import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import upstream_watch


class UpstreamWatchTests(unittest.TestCase):
    state = {'telegram_version': '13.0'}

    def test_same_version_is_not_an_update(self):
        self.assertEqual(upstream_watch.find_updates(self.state, '13.0', 'a' * 40), [])

    def test_new_telegram_version(self):
        updates = upstream_watch.find_updates(self.state, '13.0.1', 'b' * 40)
        self.assertEqual([marker for marker, _ in updates], ['telegram:13.0.1'])

    def test_older_telegram_version_is_ignored(self):
        self.assertEqual(upstream_watch.find_updates(self.state, '12.9', 'c' * 40), [])

    def test_minor_versions_compare_numerically(self):
        updates = upstream_watch.find_updates({'telegram_version': '13.9'}, '13.10', 'd' * 40)
        self.assertEqual([marker for marker, _ in updates], ['telegram:13.10'])


if __name__ == '__main__':
    unittest.main()
