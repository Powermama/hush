"""Strip embedded textures from the CC0 rose for hush's own materials.
Usage: python3 scripts/prepare-rose.py downloaded-rose.glb
Source and licence: public/art/CREDITS.md. Keeps source geometry and attribution.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys

source = Path(sys.argv[1]).read_bytes()
assert source[:4] == b'glTF' and struct.unpack_from('<I', source, 4)[0] == 2
json_length = struct.unpack_from('<I', source, 12)[0]
model = json.loads(source[20:20 + json_length])
binary = source[28 + json_length:]
used_views = {a['bufferView'] for a in model['accessors'] if 'bufferView' in a}
views, offsets, chunks = [], {}, bytearray()
for index, view in enumerate(model['bufferViews']):
    if index not in used_views:
        continue
    while len(chunks) % 4:
        chunks.append(0)
    offset = view.get('byteOffset', 0)
    offsets[index] = len(views)
    views.append({**view, 'byteOffset': len(chunks)})
    chunks.extend(binary[offset:offset + view['byteLength']])
for accessor in model['accessors']:
    if 'bufferView' in accessor:
        accessor['bufferView'] = offsets[accessor['bufferView']]
model['bufferViews'] = views
model['buffers'] = [{'byteLength': len(chunks)}]
for key in ['images', 'textures', 'samplers', 'extensionsUsed']:
    model.pop(key, None)
for material in model['materials']:
    material.pop('extensions', None)
    material['pbrMetallicRoughness'] = {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': .5}
model['asset']['extras'] = {'source_sha256': hashlib.sha256(source).hexdigest(), 'hush_changes': 'Embedded textures removed; source geometry retained. Materials and scroll poses applied at runtime.'}
encoded = json.dumps(model, separators=(',', ':')).encode()
encoded += b' ' * (-len(encoded) % 4)
chunks.extend(b'\x00' * (-len(chunks) % 4))
output = struct.pack('<III', 0x46546c67, 2, 28 + len(encoded) + len(chunks))
output += struct.pack('<II', len(encoded), 0x4e4f534a) + encoded
output += struct.pack('<II', len(chunks), 0x004e4942) + chunks
path = Path(__file__).resolve().parents[1] / 'src/landing/assets/rose.glb'
path.write_bytes(output)
print(f'{path.name}: {len(source):,} -> {len(output):,} bytes')
