# -*- coding: utf-8 -*-
"""从 Flutter SDK 的 material/icons.dart 生成运行时图标 codepoint 表。

用法（Flutter SDK 升级后重跑）：
    python3 tool/gen_material_icons.py [path/to/flutter/packages/flutter/lib/src/material/icons.dart]

不传路径时自动探测本机常见位置（windows PATH 里的 flutter / 环境变量 FLUTTER_ROOT）。
生成物：lib/features/home/presentation/components/material_icon_codepoints.dart
"""
import os
import re
import sys
import subprocess


def find_icons_dart(explicit: str) -> str:
    if explicit:
        return explicit
    env = os.environ.get('FLUTTER_ROOT')
    candidates = []
    if env:
        candidates.append(os.path.join(env, 'packages', 'flutter', 'lib', 'src', 'material', 'icons.dart'))
    try:
        root = subprocess.check_output(['flutter', 'sdk-path'], text=True, shell=True).strip()
        candidates.append(os.path.join(root, 'packages', 'flutter', 'lib', 'src', 'material', 'icons.dart'))
    except Exception:
        pass
    for p in candidates:
        if os.path.isfile(p):
            return p
    raise SystemExit('找不到 icons.dart，请显式传入路径。')


def main() -> None:
    src = find_icons_dart(sys.argv[1] if len(sys.argv) > 1 else '')
    text = open(src, encoding='utf-8').read()
    # 图标定义可能跨行（含 _sharp/_rounded/_outlined 变体），统一用跨行正则。
    found = re.findall(
        r'static const IconData (\w+) = IconData\(\s*(0x[0-9a-fA-F]+),\s*fontFamily: .MaterialIcons.',
        text,
    )
    table = {name: cp for name, cp in found}
    if not table:
        raise SystemExit('未从 %s 解析到任何图标定义' % src)

    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, '..', 'lib', 'features', 'home', 'presentation',
                       'components', 'material_icon_codepoints.dart')
    lines = [
        '// GENERATED FILE — DO NOT EDIT.',
        '// 由 tool/gen_material_icons.py 从 Flutter SDK 的 material/icons.dart 自动生成。',
        '// 作用：把 Material Icons 名字映射到字体 codepoint，使后台 JSON 里任意图标名',
        '// 都能在运行时动态构造 IconData，无需在 App 里逐个写 Icons.xxx 常量白名单。',
        '// 更新 Flutter SDK 后重跑生成脚本即可。源: %s' % os.path.basename(src),
        '',
        'const Map<String, int> kMaterialIconCodepoints = <String, int>{',
    ]
    for name in sorted(table):
        lines.append("  '%s': %s," % (name, table[name]))
    lines += ['};', '']
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines))
    print('wrote %d icons -> %s' % (len(table), os.path.normpath(out)))


if __name__ == '__main__':
    main()
