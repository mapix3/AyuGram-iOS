"""Hourly check for a new Telegram-iOS release.

Runs in GitHub Actions without any AI. It compares the upstream version with
ci/upstream.json (what is already merged here) and prints a GitHub Actions
output: `update=true` plus a markdown report when something new is out.
"""
import json
import os
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

TELEGRAM_REPO = 'https://github.com/TelegramMessenger/Telegram-iOS'
TELEGRAM_VERSIONS = 'https://raw.githubusercontent.com/TelegramMessenger/Telegram-iOS/master/versions.json'


def version_key(version):
    return tuple(int(part) for part in version.split('.'))


def ls_remote(url, *patterns):
    output = subprocess.check_output(['git', 'ls-remote', url, *patterns], text=True, timeout=120)
    return [line.split('\t', 1) for line in output.splitlines() if '\t' in line]


def find_updates(state, telegram_version, telegram_sha):
    """Returns (marker, text) when Telegram-iOS is newer than what is merged here."""
    if version_key(telegram_version) > version_key(state['telegram_version']):
        return [('telegram:' + telegram_version, 'Telegram-iOS **%s** (master `%s`), merged here: %s' % (telegram_version, telegram_sha[:10], state['telegram_version']))]
    return []


def main():
    state = json.loads((Path(__file__).parent / 'upstream.json').read_text())
    with urllib.request.urlopen(TELEGRAM_VERSIONS, timeout=60) as response:
        telegram_version = json.loads(response.read())['app']
    if not re.fullmatch(r'\d+(\.\d+)+', telegram_version):
        raise ValueError('Unexpected Telegram version in versions.json')
    telegram_sha = ls_remote(TELEGRAM_REPO, 'refs/heads/master')[0][0]
    updates = find_updates(state, telegram_version, telegram_sha)
    print('Telegram %s (%s); merged: %s' % (telegram_version, telegram_sha[:10], state['telegram_version']))
    output = os.environ.get('GITHUB_OUTPUT')
    if not output:
        print('\n'.join(text for _, text in updates) or 'No update')
        return
    with open(output, 'a') as handle:
        handle.write('update=%s\n' % ('true' if updates else 'false'))
        handle.write('marker=%s\n' % ' '.join(marker for marker, _ in updates))
        handle.write('report<<EOF\n%s\nEOF\n' % '\n'.join('- ' + text for _, text in updates))


if __name__ == '__main__':
    sys.exit(main())
