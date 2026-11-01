"""Turns the push relay's install summary into a Markdown scam report.

Official builds sideloaded with a personal certificate report no signing identity, so
every named certificate below belongs to a modified copy, a TestFlight, App Store or
enterprise install, or a paid profile with many devices.
"""
import json
import sys
from datetime import datetime, timezone

DISTRIBUTOR_SOURCES = {'testflight', 'appstore', 'enterprise'}


def counts(mapping):
    return ', '.join('%s %d' % (key, value) for key, value in sorted(mapping.items(), key=lambda item: (-item[1], item[0]))) or '-'


def cell(value):
    return str(value).replace('|', '/').replace('\n', ' ') or '-'


def suspicious(team):
    return (team['team'] != '-' and (team['installs'] >= 3 or team.get('devices', 0) > 3
            or any(source in DISTRIBUTOR_SOURCES for source in team['sources'])
            or 'modified' in team['statuses']))


def render(summary):
    lines = ['# AyuGram: scam report', '']
    lines.append('Installs: %d (active in 7 days: %d)' % (summary['total'], summary['active7d']))
    lines.append('')
    lines.append('- Source: ' + counts(summary['bySource']))
    lines.append('- Build check: ' + counts(summary['byStatus']))
    lines.append('- Builds: ' + counts(summary['byBuild']))
    lines.append('- Countries: ' + counts(summary['byCountry']))
    lines.append('')
    teams = [team for team in summary['teams'] if suspicious(team)]
    lines.append('## Suspicious certificates (%d)' % len(teams))
    lines.append('')
    if teams:
        lines.append('| Team ID | Installs | Team name | Certificate | Bundle ID | Source | Check | Countries | Builds | Devices | Last seen |')
        lines.append('|---|---|---|---|---|---|---|---|---|---|---|')
        for team in teams:
            last = datetime.fromtimestamp(team['lastSeen'] / 1000, tz=timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
            lines.append('| ' + ' | '.join(cell(value) for value in [
                team['team'], team['installs'], ', '.join(team['names']), ', '.join(team['certs']), ', '.join(team['bundles']),
                counts(team['sources']), counts(team['statuses']), counts(team['countries']), counts(team['builds']),
                team.get('devices', 0), last]) + ' |')
    else:
        lines.append('None so far.')
    lines.append('')
    lines.append('To block a certificate, run the "Block scam copy" workflow with its Team ID.')
    lines.append('')
    lines.append('## Reports from users (%d)' % len(summary['reports']))
    lines.append('')
    for report in summary['reports']:
        meta = ', '.join(part for part in [report['time'][:16].replace('T', ' '), report.get('country') or '', report.get('team') or '', report.get('teamName') or '', report.get('source') or '', report.get('status') or ''] if part)
        lines.append('- ' + cell(report['text']) + ' (' + meta + ')')
    if not summary['reports']:
        lines.append('None so far.')
    return '\n'.join(lines) + '\n'


def main():
    with open(sys.argv[1]) as handle:
        sys.stdout.write(render(json.load(handle)))


if __name__ == '__main__':
    main()
