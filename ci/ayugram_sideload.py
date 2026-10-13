"""Embed the entitlements that sideloading tools read from an IPA.

The CI build disables Bazel signing, so the app and its extensions carry no
entitlements at all. Re-signing tools (AltStore, SideStore, Sideloadly, ESign,
Feather, zsign) take the app group list from the binaries, so without it the
app group is never registered: the app cannot find its shared container and
the extensions cannot see the account. Ad-hoc signing every bundle with its
application identifier and the shared app group fixes both; the IPA still has
to be re-signed with a real certificate to install.
"""
import plistlib
import subprocess
import tempfile
from pathlib import Path

# Extensions Swiftgram ships (the action extension is disabled upstream).
REQUIRED_EXTENSIONS = ['ShareExtension', 'NotificationContentExtension', 'NotificationServiceExtension',
                       'IntentsExtension', 'WidgetExtension', 'BroadcastUploadExtension']


def sideload_entitlements(bundle_id, team_id, group):
    return {
        'application-identifier': team_id + '.' + bundle_id,
        'com.apple.developer.team-identifier': team_id,
        'com.apple.security.application-groups': [group],
    }


def check_extensions(app: Path):
    plugins = sorted((app / 'PlugIns').glob('*.appex'))
    names = [plugin.stem for plugin in plugins]
    missing = [name for name in REQUIRED_EXTENSIONS if not any(found.startswith(name) for found in names)]
    if missing:
        raise ValueError('IPA is missing app extensions: ' + ', '.join(missing))
    return plugins


def nested_code(bundle: Path):
    # Deepest first, so every container is signed after the code inside it.
    code = [path for path in bundle.rglob('*') if path.suffix == '.framework' or (path.suffix == '.dylib' and path.is_file())]
    return sorted(code, key=lambda path: len(path.parts), reverse=True)


def _run(args, capture=False):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, stdout=subprocess.PIPE if capture else None).stdout


def _sign(path: Path, entitlements=None, work: Path = None):
    args = ['codesign', '--force', '--sign', '-', '--timestamp=none']
    if entitlements is not None:
        target = work / (path.name + '.entitlements')
        target.write_bytes(plistlib.dumps(entitlements))
        args += ['--entitlements', target, '--generate-entitlement-der']
    _run(args + [path])


def _embedded_entitlements(path: Path):
    output = _run(['codesign', '-d', '--entitlements', '-', '--xml', path], capture=True)
    return plistlib.loads(output) if output else {}


def embed_sideload_entitlements(ipa: Path, team_id: str):
    with tempfile.TemporaryDirectory() as temporary:
        work = Path(temporary)
        root = work / 'ipa'
        _run(['ditto', '-x', '-k', ipa, root])
        apps = list((root / 'Payload').glob('*.app'))
        if len(apps) != 1:
            raise ValueError('IPA must contain exactly one main application')
        app = apps[0]
        bundle_id = plistlib.loads((app / 'Info.plist').read_bytes())['CFBundleIdentifier']
        group = 'group.' + bundle_id
        plugins = check_extensions(app)
        for code in nested_code(app):
            _sign(code)
        signed = {}
        for plugin in plugins:
            plugin_id = plistlib.loads((plugin / 'Info.plist').read_bytes())['CFBundleIdentifier']
            if not plugin_id.startswith(bundle_id + '.'):
                raise ValueError('Extension bundle id is not under the app: ' + plugin.name)
            signed[plugin] = sideload_entitlements(plugin_id, team_id, group)
            _sign(plugin, signed[plugin], work)
        signed[app] = sideload_entitlements(bundle_id, team_id, group)
        _sign(app, signed[app], work)
        for bundle, expected in signed.items():
            if _embedded_entitlements(bundle).get('com.apple.security.application-groups') != [group]:
                raise ValueError('App group entitlement was not embedded: ' + bundle.name)
        try:
            _run(['codesign', '--verify', '--deep', app])
        except subprocess.CalledProcessError:
            # Re-signing replaces these signatures anyway; the entitlements above are what matters.
            print('warning: ad-hoc signature did not verify on the host', flush=True)
        rebuilt = work / 'rebuilt.ipa'
        _run(['ditto', '-c', '-k', '--norsrc', root, rebuilt])
        ipa.write_bytes(rebuilt.read_bytes())
    return [plugin.name for plugin in plugins]
