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


def origin_payload(number, variant, bundle_id, env):
    repository = env.get('GITHUB_REPOSITORY', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        repository = ''
    commit = env.get('GITHUB_SHA', '')
    run = env.get('GITHUB_RUN_ID', '')
    return {
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
