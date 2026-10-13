from pathlib import Path
import re
import subprocess


def check_shared_profiles(source: Path, ci: Path):
    output = source / 'build-input/ayu-profile-checks'
    output.mkdir(parents=True, exist_ok=True)
    badges = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramClientBadges.swift'
    text = badges.read_text()
    for token in ['URLSession', 'URLRequest', 'URL(', 'http']:
        assert token not in text, 'Badges are decided on the device and never use the network: ' + token
    tests = ci / 'tests/AyuGramClientBadgesTests.swift'
    binary = output / 'badge-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', badges, tests, '-o', binary], check=True)
    subprocess.run([binary], check=True, timeout=40)
    minimum = re.search(r'^minimum_os_version\s*=\s*"([0-9.]+)"', (source / 'Telegram/BUILD').read_text(), re.M).group(1)
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum, '-sdk', sdk,
                    '-parse-as-library', '-typecheck', badges], check=True)
    print('Local badges checked with real Foundation and the minimum iOS SDK', flush=True)
    updates = source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramUpdates.swift'
    update_tests = ci / 'tests/AyuGramUpdatesTests.swift'
    update_binary = output / 'update-tests'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', updates, update_tests, '-o', update_binary], check=True)
    subprocess.run([update_binary], check=True, timeout=40)
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', '-target', 'arm64-apple-ios' + minimum, '-sdk', sdk,
                    '-parse-as-library', '-typecheck', updates], check=True)
    print('Update manifest parsing checked', flush=True)
