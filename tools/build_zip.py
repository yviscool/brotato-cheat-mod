"""
build_zip.py —— 把 mods-unpacked/<Mod>/ 打包成 ModLoader 可直接加载的 zip

内部结构必须是：  mods-unpacked/<Mod名>/manifest.json
                                 mods-unpacked/<Mod名>/mod_main.gd
                                 ...
"""

import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(ROOT, "mods-unpacked")
OUT = os.path.join(ROOT, "dist")


def build(mod_name):
    src = os.path.join(UNPACKED, mod_name)
    if not os.path.isdir(src):
        print("找不到 mod 目录:", src)
        return 1
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, "%s.zip" % mod_name)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(src):
            for f in files:
                disk = os.path.join(root, f)
                arc = os.path.join("mods-unpacked", mod_name,
                                   os.path.relpath(disk, src).replace(os.sep, "/"))
                z.write(disk, arc)
    print("打包完成:", out)
    with zipfile.ZipFile(out) as z:
        for n in z.namelist():
            print("   ", n)
    return 0


if __name__ == "__main__":
    mods = sys.argv[1:] or [d for d in os.listdir(UNPACKED)
                            if os.path.isdir(os.path.join(UNPACKED, d))]
    code = 0
    for m in mods:
        code |= build(m)
    sys.exit(code)
