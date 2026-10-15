"""Hourly check for new Telegram-iOS and Swiftgram releases.

Runs in GitHub Actions without any AI. It compares the upstream versions with
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
SWIFTGRAM_REPO = 'https://github.com/Swiftgram/Telegram-iOS'
SWIFTGRAM_TAG = re.compile(r'^(\d+(?:\.\d+)+)-(\d+)$')


def version_key(version):
    return tuple(int(part) for part in version.split('.'))


def swiftgram_key(tag):
    match = SWIFTGRAM_TAG.match(tag)
    if not match:
        return None
    return version_key(match.group(1)) + (0,) * (4 - len(match.group(1).split('.'))) + (int(match.group(2)),)


def latest_swiftgram_tag(tags):
    keyed = [(swiftgram_key(tag), tag) for tag in tags]
    keyed = [item for item in keyed if item[0] is not None]
    return max(keyed)[1] if keyed else None


def ls_remote(url, *patterns):
    output = subprocess.check_output(['git', 'ls-remote', url, *patterns], text=True, timeout=120)
    return [line.split('\t', 1) for line in output.splitlines() if '\t' in line]


def find_updates(state, telegram_version, telegram_sha, swiftgram_tag):
    """Returns (marker, text) for every upstream release newer than what is merged here."""
    updates = []
    if version_key(telegram_version) > version_key(state['telegram_version']):
        updates.append(('telegram:' + telegram_version, 'Telegram-iOS **%s** (master `%s`), merged here: %s' % (telegram_version, telegram_sha[:10], state['telegram_version'])))
    if swiftgram_tag and swiftgram_key(swiftgram_tag) > swiftgram_key(state['swiftgram_tag']):
        updates.append(('swiftgram:' + swiftgram_tag, 'Swiftgram tag **%s**, merged here: %s' % (swiftgram_tag, state['swiftgram_tag'])))
    return updates


def main():
    state = json.loads((Path(__file__).parent / 'upstream.json').read_text())
    with urllib.request.urlopen(TELEGRAM_VERSIONS, timeout=60) as response:
        telegram_version = json.loads(response.read())['app']
    if not re.fullmatch(r'\d+(\.\d+)+', telegram_version):
        raise ValueError('Unexpected Telegram version in versions.json')
    telegram_sha = ls_remote(TELEGRAM_REPO, 'refs/heads/master')[0][0]
    tags = [ref.rsplit('/', 1)[1] for _, ref in ls_remote(SWIFTGRAM_REPO, 'refs/tags/*') if not ref.endswith('^{}')]
    updates = find_updates(state, telegram_version, telegram_sha, latest_swiftgram_tag(tags))
    print('Telegram %s (%s), Swiftgram %s; merged: %s' % (telegram_version, telegram_sha[:10], latest_swiftgram_tag(tags), state))
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
