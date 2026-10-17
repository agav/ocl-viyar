"""Decodes a Bazis2Viyar export script ("Экспорт проекта ViyarPro.js") into readable JavaScript.

The script is wrapped with Bazis-Mebelshchik's system.secureExec("<base64>"): base64 -> 5-byte
header (01 00 00 ff 01) -> zlib -> a small binary record whose payload is the UTF-16LE source,
prefixed by its length in characters (uint32 LE). Nothing is encrypted.

Usage: python3 -I decode.py "<path to Экспорт проекта ViyarPro.js>" <output.js>
"""
import base64
import re
import struct
import sys
import zlib

HEADER = bytes.fromhex('010000ff01')


def decode(wrapped):
    start = wrapped.index('secureExec("')
    end = wrapped.index('");', start)
    raw = base64.b64decode(''.join(re.findall(r'"([A-Za-z0-9+/=]*)"', wrapped[start:end])))
    if raw[:5] != HEADER:
        raise ValueError(f'unexpected header {raw[:5].hex()} (expected {HEADER.hex()}): format changed')
    data = zlib.decompress(raw[5:])
    # the source starts with "var " in UTF-16LE, right after its uint32 length
    i = data.index('var '.encode('utf-16-le'))
    length = struct.unpack('<I', data[i - 4:i])[0]
    return data[i:i + 2 * length].decode('utf-16-le')


def main():
    src, out = sys.argv[1], sys.argv[2]
    with open(src, encoding='utf-8-sig') as f:
        source = decode(f.read())
    with open(out, 'w', encoding='utf-8', newline='') as f:
        f.write(source)
    version = re.search(r"SCRIPT_VERSION = '([^']+)'", source)
    print(f'{out}: {len(source.splitlines())} lines, SCRIPT_VERSION {version.group(1) if version else "?"}')


if __name__ == '__main__':
    main()
