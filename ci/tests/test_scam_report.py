import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('ayugram_scam_report', Path(__file__).resolve().parents[1] / 'ayugram_scam_report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def team(name, installs, sources, statuses, devices=1, certs=()):
    return {'team': name, 'installs': installs, 'devices': devices, 'names': [], 'certs': list(certs), 'profiles': [], 'bundles': [],
            'countries': {'KZ': installs}, 'sources': sources, 'statuses': statuses, 'builds': {'207601': installs}, 'lastSeen': 1767225600000}


class ScamReportTests(unittest.TestCase):
    def test_only_distributors_are_listed(self):
        summary = {'total': 9, 'active7d': 8, 'bySource': {'sideload': 5, 'testflight': 4}, 'byStatus': {'official': 5, 'modified': 4},
                   'byBuild': {'207601': 9}, 'byCountry': {'KZ': 9}, 'teams': [
                       team('SCAM123456', 4, {'testflight': 4}, {'modified': 4}, certs=['Apple Distribution: Evil | LLC']),
                       team('-', 5, {'sideload': 5}, {'official': 5}),
                       team('OWN1234567', 1, {'sideload': 1}, {'official': 1}),
                   ], 'reports': [{'time': '2026-11-01T10:00:00.000Z', 'text': '@scammer sold me an Apple ID', 'team': 'SCAM123456', 'teamName': '', 'source': 'testflight', 'status': 'modified', 'build': 207601, 'country': 'KZ'}]}
        text = report.render(summary)
        self.assertIn('| SCAM123456 | 4 |', text)
        self.assertIn('Apple Distribution: Evil / LLC', text, 'Pipes cannot break the table')
        self.assertNotIn('OWN1234567', text, 'A personal certificate with one official install is not listed')
        self.assertIn('Suspicious certificates (1)', text)
        self.assertIn('- @scammer sold me an Apple ID (2026-11-01 10:00, KZ, SCAM123456, testflight, modified)', text)


if __name__ == '__main__':
    unittest.main()
