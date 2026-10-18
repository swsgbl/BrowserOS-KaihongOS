"""P37: regenerate D:\\v1tmp\\final_ids.json from the ACTUAL id map baked into
hvigor's RestoolV2 resources.index (the ids modules.abc really references).

Background: ResourceTable.txt / ids_map/id_defined.json carry a DIFFERENT
(insertion-order-ish) numbering that does NOT match the V2 index records.
The V2 record layout observed: <namelen:u32><name><id:u32 0x01xxxxxx><meta:u32>.
Blank-icons root cause: V1 pack pinned the wrong table.
"""
import json
import os
import struct
import sys

PROJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
V2 = os.path.join(PROJ, 'entry', 'build', 'default', 'intermediates', 'res', 'default',
                  'resources.index')
OUT = r'D:\v1tmp\final_ids.json'

TYPE_BY_NAME = {
    'app_name': 'string', 'EntryAbility_label': 'string', 'EntryAbility_desc': 'string',
    'module_desc': 'string', 'internet_permission_reason': 'string',
    'file_access_permission_reason': 'string', 'storage_permission_reason': 'string',
    'start_window_background': 'color',
}


# module.json 引用的 13 项：沿用 P8 期稳定值（launcher 图标/标签多周实证正常；
# V2 字符串区记录结构不同，解析不可靠）
BASE13 = {
    'app_name': ('string', 0x01000001), 'EntryAbility_label': ('string', 0x01000002),
    'EntryAbility_desc': ('string', 0x01000003), 'module_desc': ('string', 0x01000004),
    'internet_permission_reason': ('string', 0x01000005),
    'file_access_permission_reason': ('string', 0x01000006),
    'storage_permission_reason': ('string', 0x01000007),
    'start_window_background': ('color', 0x01000008),
    'app_icon': ('media', 0x01000009), 'app_icon_48': ('media', 0x0100000a),
    'app_icon_96': ('media', 0x0100000b), 'app_icon_192': ('media', 0x0100000c),
    'app_icon_216': ('media', 0x0100000d),
}


def main():
    data = open(V2, 'rb').read()
    if not data.startswith(b'RestoolV2'):
        print('not a V2 index:', data[:16])
        return 1
    found = {}
    i = 0
    n = len(data)
    while i + 8 <= n:
        (ln,) = struct.unpack_from('<I', data, i)
        if 0 < ln < 64 and i + 4 + ln + 8 <= n:
            name = data[i + 4:i + 4 + ln]
            (rid, _meta) = struct.unpack_from('<II', data, i + 4 + ln)
            if (0x0100000E <= rid <= 0x01FFFFFF and name.startswith(b'ic_')
                    and name.replace(b'_', b'a').isalnum()):
                found[name.decode()] = rid
                i += 4 + ln + 8
                continue
        i += 1
    print('parsed %d ic_* entries from V2 index' % len(found))
    for probe in ('ic_add', 'ic_close', 'ic_zap'):
        print(' ', probe, hex(found.get(probe, 0)))
    merged = dict(BASE13)
    for name, rid in found.items():
        merged[name] = ('media', rid)
    record = [{'id': '0x%08X' % rid, 'type': t, 'name': name}
              for name, (t, rid) in sorted(merged.items())]
    json.dump({'record': record}, open(OUT, 'w', encoding='utf-8'), indent=2)
    print('wrote %s with %d entries' % (OUT, len(record)))
    return 0 if len(found) >= 30 else 1


if __name__ == '__main__':
    sys.exit(main())
