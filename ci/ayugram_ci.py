#!/usr/bin/env python3
"""Build the pinned Swiftgram checkout. Runs on macOS; helpers are testable anywhere."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile

UPSTREAM = 'Swiftgram/Telegram-iOS@cf8b23beaaac4126a396337ac2d5be13f9f76b66'


def run(args, cwd=None, capture=False):
    # Commands contain filenames and public options, never secret values.
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), cwd=cwd, check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout


def build_configuration(env):
    required = ['TELEGRAM_API_ID', 'TELEGRAM_API_HASH', 'APPLE_TEAM_ID', 'APP_BUNDLE_ID']
    missing = [key for key in required if not env.get(key, '').strip()]
    if missing:
        raise ValueError('Missing GitHub Secrets: ' + ', '.join(missing))
    values = {key: env[key].strip() for key in required}
    checks = {
        'TELEGRAM_API_ID': r'[1-9][0-9]{0,9}',
        'TELEGRAM_API_HASH': r'[0-9a-fA-F]{32}',
        'APPLE_TEAM_ID': r'[A-Z0-9]{10}',
        'APP_BUNDLE_ID': r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
    }
    for name, pattern in checks.items():
        if not re.fullmatch(pattern, values[name]):
            raise ValueError('Invalid format for ' + name)  # Do not print its value.
    if int(values['TELEGRAM_API_ID']) > 2147483647:
        raise ValueError('TELEGRAM_API_ID exceeds Int32')
    return {
        'bundle_id': values['APP_BUNDLE_ID'],
        'api_id': values['TELEGRAM_API_ID'],
        'api_hash': values['TELEGRAM_API_HASH'],
        'team_id': values['APPLE_TEAM_ID'],
        'app_center_id': '0', 'is_internal_build': 'true',
        'is_appstore_build': 'false', 'appstore_id': '0',
        'app_specific_url_scheme': 'tg', 'premium_iap_product_id': '',
        'enable_siri': False, 'enable_icloud': False, 'sg_config': '',
    }


def verify_ipa(path, bundle_id):
    with zipfile.ZipFile(path) as archive:
        corrupt = archive.testzip()
        if corrupt:
            raise ValueError('Corrupt IPA')
        mains = [n for n in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', n)]
        if len(mains) != 1:
            raise ValueError('IPA must contain exactly one main application')
        info = plistlib.loads(archive.read(mains[0]))
        if info.get('CFBundleIdentifier') != bundle_id:
            raise ValueError('Unexpected bundle identifier')
        if 'iPhoneOS' not in info.get('CFBundleSupportedPlatforms', []):
            raise ValueError('IPA is not a device build (simulator artifacts cannot be installed)')
        executable = mains[0].rsplit('/', 1)[0] + '/' + info['CFBundleExecutable']
        if executable not in archive.namelist() or archive.getinfo(executable).file_size == 0:
            raise ValueError('Missing application executable')
        return {key: info.get(key) for key in ['CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'CFBundleSupportedPlatforms']}


def cleanup(source):
    # Source is a disposable Actions checkout. Do not remove source or user files.
    for relative in ['build-input/ayugram-ci-configuration.json',
                     'build-input/configuration-repository/variables.bzl']:
        (source / relative).unlink(missing_ok=True)


def save_manifest(path, manifest):
    path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')


def build(source, ci, output, env):
    if sys.platform != 'darwin':
        raise RuntimeError('The iOS build requires a macOS runner with Xcode')
    configuration = env.get('AYUGRAM_CONFIGURATION', 'release_arm64')
    if configuration not in ['release_arm64', 'debug_arm64']:
        raise ValueError('Unknown device configuration')
    variant = env.get('AYUGRAM_VARIANT', 'standard')
    if variant not in ['standard', 'custom']:
        raise ValueError('Unknown app variant')
    config = build_configuration(env)
    head = run(['git', 'rev-parse', 'HEAD'], cwd=source, capture=True).strip()
    submodules = run(['git', 'submodule', 'status', '--recursive'], cwd=source, capture=True)
    if any(line.startswith(('-', '+', 'U')) for line in submodules.splitlines()):
        raise ValueError('Submodules are missing or do not match their pinned revisions')
    versions = json.loads((source / 'versions.json').read_text())
    xcode = run(['xcodebuild', '-version'], capture=True).strip()
    if xcode.splitlines()[0] != 'Xcode ' + versions['xcode']:
        raise ValueError('Xcode does not match versions.json')

    output.mkdir(parents=True, exist_ok=True)
    build_input = source / 'build-input'
    build_input.mkdir(exist_ok=True)
    config_path = build_input / 'ayugram-ci-configuration.json'
    rc_path = source / '.bazelrc'
    original_rc = rc_path.read_bytes()
    # This pinned rules_apple revision checks profile embedding independently
    # of disable_legacy_signing. Gate only that partial for unsigned CI.
    rules_path = source / 'build-system/bazel-rules/rules_apple/apple/internal/ios_rules.bzl'
    original_rules = rules_path.read_bytes()
    if hashlib.sha256(original_rules).hexdigest() != 'b6776b1c10a2c965f01259dd95ebe1b045afc5e22b3446b8ae81d44f11c3a7da':
        raise ValueError('Unexpected rules_apple iOS rules revision')
    # Builds from this repository start above every earlier build so update checks compare correctly.
    number = 200000 + int(env.get('GITHUB_RUN_NUMBER', '1')) * 100 + int(env.get('GITHUB_RUN_ATTEMPT', '1'))
    manifest = {'upstream': UPSTREAM, 'source_commit': head,
                'configuration': configuration, 'signing': 'ad-hoc with app group entitlements; requires re-signing to install',
                'variant': variant, 'xcode': xcode, 'versions': versions, 'build_number': number,
                'status': 'running'}
    manifest_path = output / 'build-manifest.json'
    save_manifest(manifest_path, manifest)
    try:
        rules_text = original_rules.decode('utf-8')
        profile_guard = ('    if platform_prerequisites.platform.is_device:\n'
                         '        processor_partials.append(\n'
                         '            partials.provisioning_profile_partial(')
        if profile_guard not in rules_text:
            raise ValueError('Pinned rules_apple profile guard changed')
        rules_text = rules_text.replace(profile_guard, profile_guard.replace(
            'platform.is_device:',
            'platform.is_device and "disable_legacy_signing" not in features:'))
        rules_path.write_text(rules_text, encoding='utf-8')
        config_path.write_text(json.dumps(config), encoding='utf-8')
        config_path.chmod(0o600)
        # Make.py's --bazelArguments is parsed but unused at the audited revision.
        # .bazelrc applies to BOTH project generation and the full Bazel build.
        # disable_legacy_signing is supported by the pinned rules_apple submodule.
        # Do not disable extensions: preserve Swiftgram's application functionality.
        rc_path.write_bytes(original_rc + b'\n# Temporary AyuGram unsigned CI settings\n'
                            # Make.py clears PATH before invoking Bazel. Genrules
                            # need Homebrew's ccache for TDLib's CMake launchers.
                            b'build --action_env=PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\n'
                            b'build --//Telegram:disableProvisioningProfiles=true\n'
                            b'build --features=disable_legacy_signing\n'
                            b'build --jobs=2\n'
                            b'build --worker_max_instances=SwiftCompile=1\n'
                            # A module with many warnings can exceed Bazel's 1 MB output cap,
                            # which hides its compile errors from the log.
                            b'build --experimental_ui_max_stdouterr_bytes=-1\n')
        # Let the repository download and checksum its own Bazel, not brew's latest.
        sys.path.insert(0, str(source / 'build-system/Make'))
        from BazelLocation import locate_bazel, calculate_sha256
        os.chdir(source)  # The upstream locator reads versions.json from cwd.
        bazel = Path(locate_bazel(str(source), None, None))
        expected_version, expected_hash = versions['bazel'].split(':', 1)
        if calculate_sha256(str(bazel)) != expected_hash:
            raise ValueError('Downloaded Bazel does not match versions.json SHA256')
        bazel_version = run([bazel, '--version'], capture=True).strip()
        if bazel_version != 'bazel ' + expected_version:
            raise ValueError('Wrong Bazel version')
        manifest['bazel'] = bazel_version
        manifest['bazel_sha256'] = expected_hash
        make = [sys.executable, '-u', 'build-system/Make/Make.py', '--bazel=' + str(bazel)]
        # The workflow restores and saves this directory between runs, so a rebuild only compiles what changed.
        cache = env.get('AYUGRAM_BAZEL_CACHE')
        if cache:
            make.append('--cacheDir=' + cache)
        # This source supplies the configuration model without importing fake certs.
        # Actual provisioning and codesigning are disabled above in Bazel.
        common = ['--configurationPath=' + str(config_path), '--xcodeManagedCodesigning', '--buildNumber=' + str(number)]
        # Checks run against the repository's own source before the expensive build.
        test = source / 'build-input/ayu-settings-tests'
        run(['xcrun', 'swiftc', '-swift-version', '5', '-D', 'AYUGRAM_CLIENT_EXTRAS', '-D', 'AYUGRAM_REFINEMENTS', '-D', 'AYUGRAM_EXTRA_SETTINGS',
             source / 'Swiftgram/SGSimpleSettings/Sources/AyuGramSettings.swift',
             ci / 'tests/AyuGramSettingsTests.swift', '-o', test], cwd=source)
        run([test], cwd=source)
        from ayugram_profile_checks import check_shared_profiles
        check_shared_profiles(source, ci)
        from ayugram_receipt_checks import check_receipts
        check_receipts(source)
        from ayugram_emoji_checks import check_link_free_emoji
        check_link_free_emoji(source)
        if variant == 'custom':
            from ayugram_compatibility import check_custom_compatibility
            check_custom_compatibility(source)
            from ayugram_ui_checks import check_ui_regressions
            check_ui_regressions(source)
        from ayugram_history_checks import check_history
        check_history(source)
        from ayugram_ghost_checks import check_ghost_and_content
        check_ghost_and_content(source, variant)
        from ayugram_branding import prepare_branding, verify_branding_ipa
        prepare_branding(source)
        run(make + ['generateProject'] + common + ['--disableProvisioningProfiles'], cwd=source)
        if not (source / 'Telegram/Swiftgram.xcodeproj').is_dir():
            raise ValueError('Make.py did not generate Telegram/Swiftgram.xcodeproj')
        run(make + ['build', '--continueOnError'] + common + ['--configuration=' + configuration], cwd=source)
        ipa = source / 'bazel-bin/Telegram/Swiftgram.ipa'
        if not ipa.is_file():
            raise FileNotFoundError('Make.py succeeded but Swiftgram.ipa is missing')
        verify_ipa(ipa, config['bundle_id'])
        verify_branding_ipa(ipa)
        target = output / ('AyuGram-' + variant + '-unsigned.ipa')
        shutil.copyfile(ipa, target)
        target.chmod(0o644)
        # Sideloading tools read the app group from the binaries; embed it for the app and every extension.
        from ayugram_sideload import embed_sideload_entitlements
        manifest['extensions'] = embed_sideload_entitlements(target, config['team_id'])
        manifest['app'] = verify_ipa(target, config['bundle_id'])
        manifest.update(ipa=target.name, sha256=hashlib.sha256(target.read_bytes()).hexdigest())
        print('Verified device IPA: ' + target.name, flush=True)
        manifest['status'] = 'success'
    except BaseException as error:
        manifest['status'] = 'failed'
        # Avoid serializing arbitrary tool output that might contain credentials.
        manifest['failure_type'] = type(error).__name__
        raise
    finally:
        rules_path.write_bytes(original_rules)
        rc_path.write_bytes(original_rc)
        cleanup(source)
        save_manifest(manifest_path, manifest)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--ci', type=Path, default=Path('.'))
    parser.add_argument('--output', type=Path, default=Path('artifacts'))
    parser.add_argument('--cleanup-only', action='store_true')
    args = parser.parse_args()
    if args.cleanup_only:
        cleanup(args.source.resolve())
    else:
        build(args.source.resolve(), args.ci.resolve(), args.output.resolve(), os.environ)
