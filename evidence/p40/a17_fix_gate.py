"""P40: restore icon gate hard-fail - line-index surgery (bytes are valid utf-8 but
contain GBK mojibake chars; simple regex on replaced-decode failed due to \r\n)."""
import sys
sys.stdout.reconfigure(encoding='utf-8')
P = r"D:\BrowserOS - KaihongOS\tools\smoke_reg.py"
lines = open(P, encoding='utf-8', errors='replace').read().splitlines(keepends=True)
# find the P39 marker line index
i39 = next(i for i, l in enumerate(lines) if 'P39' in l and 'SKIP' not in l and 'AceImage' in l) if any(
    'P39' in l and 'SKIP' not in l and 'AceImage' in l for l in lines) else None
# more robust: find 'hdc.sh(' 'hilog -x', 60)' inside check_icon_render region
i_start = next(i for i, l in enumerate(lines) if 'def check_icon_render' in l)
i_hilog = next(i for i, l in enumerate(lines) if i > i_start and "'hilog -x', 60" in l)
# end of the else block: the line with "record('9.icon pixel gate', False, 'icon %s non-bg %.1f%% (<15)'"
i_end = next(i for i, l in enumerate(lines) if i > i_hilog and "non-bg %.1f%% (<15)" in l)
i_else = next(i for i, l in enumerate(lines) if i_start < i < i_hilog and l.strip() == 'else:')
assert lines[i_else].strip() == 'else:', repr(lines[i_else])
print('replacing lines', i_else, '..', i_end)
print('--- old block:')
for l in lines[i_else:i_end + 1]:
    print(repr(l[:100]))
new_block = [
    "        else:\n",
    "            # P40: root cause FIXED - build_api23_hap.py now emits an all-STORED zip\n",
    "            # (KaihongOS resmgr cannot read DEFLATED hap entries; that blanked every\n",
    "            # in-app icon). Icon blanks are a real regression again - hard fail, no SKIP.\n",
    "            record('9.icon pixel gate', False, 'icon %s non-bg %.1f%% (<15)' % (img_b, pct))\n",
]
lines2 = lines[:i_else] + new_block + lines[i_end + 1:]
out = ''.join(lines2)
open(P, 'w', encoding='utf-8', newline='').write(out)
import ast
ast.parse(out)
print('--- patched & syntax OK')
