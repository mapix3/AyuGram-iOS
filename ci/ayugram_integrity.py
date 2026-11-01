"""Fingerprints the code of an AyuGram IPA.

Each Mach-O image of the app (the main executable, frameworks and dylibs, not extensions)
is reduced to the SHA-256 of its __TEXT,__text section. Re-signing changes the code
signature but never that section, so a sideloaded official build keeps its fingerprint
while a rebuilt, patched or injected one does not. The app compares the images it has
loaded with this list, published next to the IPA in the build release.
"""
import hashlib
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import PurePosixPath

MH_MAGIC_64 = 0xfeedfacf
FAT_MAGIC = 0xcafebabe
FAT_MAGIC_64 = 0xcafebabf
CPU_TYPE_ARM64 = 0x0100000c
LC_SEGMENT_64 = 0x19


def text_section_hash(data: bytes):
    if len(data) < 32:
        return None
    base = 0
    magic = struct.unpack_from('>I', data, 0)[0]
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        count = struct.unpack_from('>I', data, 4)[0]
        base = None
        for index in range(count):
            if magic == FAT_MAGIC:
                cputype, _, offset, _, _ = struct.unpack_from('>iiIII', data, 8 + index * 20)
            else:
                cputype, _, offset, _, _, _ = struct.unpack_from('>iiQQII', data, 8 + index * 32)
            if cputype == CPU_TYPE_ARM64:
                base = offset
                break
        if base is None:
            return None
    if struct.unpack_from('<I', data, base)[0] != MH_MAGIC_64:
        return None
    ncmds = struct.unpack_from('<I', data, base + 16)[0]
    cursor = base + 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', data, cursor)
        if cmd == LC_SEGMENT_64:
            segname = data[cursor + 8:cursor + 24].rstrip(b'\0')
            nsects = struct.unpack_from('<I', data, cursor + 64)[0]
            if segname == b'__TEXT':
                for section in range(nsects):
                    start = cursor + 72 + section * 80
                    sectname = data[start:start + 16].rstrip(b'\0')
                    if sectname == b'__text':
                        size = struct.unpack_from('<Q', data, start + 40)[0]
                        offset = struct.unpack_from('<I', data, start + 48)[0]
                        chunk = data[base + offset:base + offset + size]
                        if len(chunk) != size:
                            return None
                        return hashlib.sha256(chunk).hexdigest()
        cursor += cmdsize
    return None


def fingerprint(ipa_path: str, build: int) -> dict:
    images = {}
    with zipfile.ZipFile(ipa_path) as archive:
        names = archive.namelist()
        apps = sorted({PurePosixPath(n).parts[1] for n in names if n.startswith('Payload/') and len(PurePosixPath(n).parts) > 2 and PurePosixPath(n).parts[1].endswith('.app')})
        if len(apps) != 1:
            raise ValueError('Expected one app in the IPA, found %d' % len(apps))
        root = 'Payload/' + apps[0] + '/'
        info = plistlib.loads(archive.read(root + 'Info.plist'))
        candidates = [info['CFBundleExecutable']]
        for name in names:
            if not name.startswith(root + 'Frameworks/') or name.endswith('/'):
                continue
            relative = name[len(root):]
            parts = PurePosixPath(relative).parts
            if len(parts) == 2 and parts[1].endswith('.dylib'):
                candidates.append(relative)
            elif len(parts) == 3 and parts[1].endswith('.framework') and parts[2] == parts[1][:-len('.framework')]:
                candidates.append(relative)
        for relative in sorted(set(candidates)):
            digest = text_section_hash(archive.read(root + relative))
            if digest:
                images[relative] = digest
    if info['CFBundleExecutable'] not in images:
        raise ValueError('The main executable has no __TEXT,__text section')
    return {'build': build, 'images': images}


def main():
    if len(sys.argv) != 3:
        print('usage: ayugram_integrity.py <ipa> <build number>', file=sys.stderr)
        sys.exit(2)
    print(json.dumps(fingerprint(sys.argv[1], int(sys.argv[2])), indent=1, sort_keys=True))


if __name__ == '__main__':
    main()
