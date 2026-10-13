"""Produce native Apple icon assets from the user's unmodified source images."""
import base64
import json
import plistlib
from pathlib import Path
import subprocess
import struct
import zipfile


def prepare_branding(source: Path):
    source = source.resolve()
    data = json.loads((source / 'Swiftgram/AyuBranding/icons.json').read_text(encoding='utf-8'))
    if set(data) != {'AyuClassic', 'AyuPurple', 'AyuRed'}:
        raise ValueError('Unexpected icon manifest')
    temporary = source / 'build-input/ayugram-icons'
    temporary.mkdir(parents=True, exist_ok=True)

    def png(image, target, size):
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['sips', '-s', 'format', 'png', '-z', str(size), str(size), str(image), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)

    for name, encoded in data.items():
        contents = base64.b64decode(encoded, validate=True)
        if len(contents) > 1024 * 1024 or not contents.startswith(b'\xff\xd8'):
            raise ValueError('Invalid source icon')
        image = temporary / (name + '.jpg')
        image.write_bytes(contents)
        alternate = source / 'Telegram/Telegram-iOS' / (name + '.alticon')
        for scale, size in [(2, 120), (3, 180)]:
            png(image, alternate / (name + '@' + str(scale) + 'x.png'), size)
        preview = source / 'Swiftgram/SGAppBadgeAssets/Images.xcassets' / (name + 'Mark.imageset')
        entries = []
        for scale in [2, 3]:
            filename = name + '@' + str(scale) + 'x.png'
            png(image, preview / filename, 30 * scale)
            entries.append({'idiom': 'universal', 'filename': filename, 'scale': str(scale) + 'x'})
        (preview / 'Contents.json').write_text(json.dumps({'images': entries, 'info': {'version': 1, 'author': 'xcode'}}, indent=2))

    composer = source / 'Telegram/Telegram-iOS/AyuGram.icon'
    template = json.loads((source / 'Telegram/Telegram-iOS/Swiftgram.icon/icon.json').read_text())
    template['fill']['linear-gradient'] = ['srgb:0.19,0.15,0.28,1.0', 'srgb:0.19,0.15,0.28,1.0']
    for group in template['groups']:
        for layer in group['layers']:
            layer['image-name'] = 'AyuClassic.png'
            layer['name'] = 'AyuGram'
            layer['glass'] = False
            layer['opacity-specializations'] = [{'value': 1}]
        group['translucency'] = {'enabled': False, 'value': 0}
    png(temporary / 'AyuClassic.jpg', composer / 'Assets/AyuClassic.png', 1024)
    (composer / 'icon.json').write_text(json.dumps(template, indent=2))


def verify_branding_ipa(path):
    with zipfile.ZipFile(path) as archive:
        mains = [name for name in archive.namelist() if name.startswith('Payload/') and name.endswith('.app/Info.plist') and name.count('/') == 2]
        if len(mains) != 1:
            raise ValueError('Missing main app plist')
        info = plistlib.loads(archive.read(mains[0]))
        if info.get('CFBundleDisplayName') != 'AyuGram':
            raise ValueError('Unexpected app display name')
        alternates = info.get('CFBundleIcons', {}).get('CFBundleAlternateIcons', {})
        if not {'AyuClassic', 'AyuPurple', 'AyuRed'}.issubset(alternates):
            raise ValueError('AyuGram alternate icons were not included')
        bundle = mains[0].removesuffix('Info.plist')
        for name in ['AyuClassic', 'AyuPurple', 'AyuRed']:
            if alternates[name].get('CFBundleIconFiles') != [name]:
                raise ValueError('Unexpected alternate icon file reference: ' + name)
            for scale, pixels in [(2, 120), (3, 180)]:
                path = bundle + name + '@' + str(scale) + 'x.png'
                if path not in archive.namelist():
                    raise ValueError('Missing alternate icon image: ' + path)
                image = archive.read(path)
                if png_dimensions(image) != (pixels, pixels):
                    raise ValueError('Invalid alternate icon image: ' + path)


def png_dimensions(image):
    if image[:8] != b'\x89PNG\r\n\x1a\n':
        return None
    offset = 8
    while offset + 12 <= len(image):
        length = struct.unpack('>I', image[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(image):
            return None
        if image[offset + 4:offset + 8] == b'IHDR':
            return struct.unpack('>II', image[offset + 8:offset + 16]) if length == 13 else None
        offset = end
    return None
