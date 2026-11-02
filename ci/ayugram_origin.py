import hashlib
import json
import os
import re

SEAL_PATH = 'Swiftgram/SGSimpleSettings/Sources/AyuGramSecurity.swift'
SEAL_LINE = re.compile(r'^private let ayuGramSeal: \[UInt8\] = \[[0-9, ]*\]$', re.M)


def signature(value):
    if not value:
        return ''
    return hashlib.sha256(('ayugram-sig|' + value).encode('utf-8')).hexdigest()[:32]


def seal(payload, nonce):
    if len(nonce) != 16:
        raise ValueError('The seal nonce has 16 bytes')
    plain = json.dumps(payload, separators=(',', ':'), sort_keys=True).encode('utf-8')
    out = bytearray(nonce)
    block = b''
    for index, byte in enumerate(plain):
        if index % 32 == 0:
            block = hashlib.sha256(b'ayugram-origin' + nonce + (index // 32).to_bytes(4, 'big')).digest()
        out.append(byte ^ block[index % 32])
    return bytes(out)


def open_seal(data):
    nonce = bytes(data[:16])
    plain = bytearray()
    block = b''
    for index, byte in enumerate(data[16:]):
        if index % 32 == 0:
            block = hashlib.sha256(b'ayugram-origin' + nonce + (index // 32).to_bytes(4, 'big')).digest()
        plain.append(byte ^ block[index % 32])
    return json.loads(bytes(plain))


def detect_ci(env):
    if env.get('GITHUB_ACTIONS') == 'true' or env.get('GITHUB_REPOSITORY'):
        return 'github', env.get('GITHUB_SERVER_URL') or 'https://github.com', env.get('GITHUB_REPOSITORY', ''), env.get('GITHUB_SHA', ''), env.get('GITHUB_RUN_ID', '')
    if env.get('GITLAB_CI'):
        return 'gitlab', env.get('CI_SERVER_URL', ''), env.get('CI_PROJECT_PATH', ''), env.get('CI_COMMIT_SHA', ''), env.get('CI_PIPELINE_ID', '')
    if env.get('BITRISE_IO') or env.get('BITRISE_BUILD_NUMBER'):
        return 'bitrise', '', '', env.get('BITRISE_GIT_COMMIT', ''), env.get('BITRISE_BUILD_NUMBER', '')
    if env.get('CM_BUILD_ID'):
        return 'codemagic', '', '', env.get('CM_COMMIT', ''), ''
    if env.get('CIRCLECI'):
        slug = '/'.join(part for part in [env.get('CIRCLE_PROJECT_USERNAME', ''), env.get('CIRCLE_PROJECT_REPONAME', '')] if part)
        return 'circleci', '', slug, env.get('CIRCLE_SHA1', ''), env.get('CIRCLE_BUILD_NUM', '')
    if env.get('CI_XCODE_CLOUD') or env.get('CI_XCODEBUILD_ACTION'):
        return 'xcode-cloud', '', '', env.get('CI_COMMIT', ''), env.get('CI_BUILD_NUMBER', '')
    if env.get('CI'):
        return 'ci', '', '', '', ''
    return 'local', '', '', '', ''


def origin_payload(number, variant, bundle_id, env):
    platform, server, repository, commit, run = detect_ci(env)
    if not re.fullmatch(r'[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+', repository) or len(repository) > 120:
        repository = ''
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(:[0-9]{1,5})?', server):
        server = ''
    return {
        'p': platform,
        'h': server,
        'r': repository,
        'b': int(number),
        'v': variant,
        'c': commit[:12] if re.fullmatch(r'[0-9a-f]{7,40}', commit) else '',
        'u': run if run.isdigit() else '',
        'i': signature(bundle_id),
    }


def prepare_origin(source, number, variant, bundle_id, env, nonce=None):
    data = seal(origin_payload(number, variant, bundle_id, env), nonce if nonce is not None else os.urandom(16))
    path = source / SEAL_PATH
    text = path.read_text(encoding='utf-8')
    replacement = 'private let ayuGramSeal: [UInt8] = [' + ', '.join(str(byte) for byte in data) + ']'
    updated, count = SEAL_LINE.subn(lambda _: replacement, text)
    if count != 1:
        raise ValueError('The origin seal line is missing')
    path.write_text(updated, encoding='utf-8')
    return data
