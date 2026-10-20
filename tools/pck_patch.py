"""
pck_patch.py —— 把 Godot Mod Loader 格式的 mod 目录写进 Brotato 的 Brotato.pck

用法：
    python tools/pck_patch.py                       # 自动找到游戏目录并安装
    python tools/pck_patch.py --game "D:\\game\\Brotato"
    python tools/pck_patch.py --game "..." --mod mods-unpacked/Local-Cheat

原理（Brotato.pck 的实际格式，已实测验证）：
    0x00  "GDPC"
    0x04  u32  pack_version (=1)
    0x08  u32  ver_major   (=3)
    0x0C  u32  ver_minor   (=7)
    0x10  u32  pack_flags  (=0)
    0x14  u64  file_base   (=0)
    0x54  u32  file_count          <-- 文件表条目数在 0x54(84)
    0x58  file table:
              u32 path_len
              bytes path (path_len 字节，含结尾 \\0，按 4 字节对齐填充)
              u64 offset   (文件在 pck 中的绝对偏移)
              u64 size
              u8[16] md5
    之后是所有文件数据（紧跟文件表）
追加文件时：文件表变长 -> 旧文件偏移整体平移 -> 新文件数据追加到末尾。
"""

import argparse
import hashlib
import os
import shutil
import struct
import sys

HEADER_SIZE = 88          # 文件表起始偏移
COUNT_OFFSET = 84         # file_count 所在偏移


def parse_pck(data):
    assert data[:4] == b"GDPC", "不是有效的 PCK 文件"
    count = struct.unpack("<i", data[COUNT_OFFSET:COUNT_OFFSET + 4])[0]
    off = HEADER_SIZE
    entries = []
    for _ in range(count):
        (ln,) = struct.unpack("<i", data[off:off + 4])
        off += 4
        raw = data[off:off + ln]
        off += ln
        path = raw.rstrip(b"\x00").decode("utf-8", "replace")
        (o,) = struct.unpack("<q", data[off:off + 8])
        off += 8
        (s,) = struct.unpack("<q", data[off:off + 8])
        off += 8
        md5 = data[off:off + 16]
        off += 16
        entries.append([path, raw, o, s, md5])
    return entries, off


def encode_path(path):
    b = path.encode("utf-8") + b"\x00"
    while len(b) % 4:
        b += b"\x00"
    return b


DEFAULT_DIRS = [
    r"D:\game\Brotato",
    r"C:\Program Files (x86)\Steam\steamapps\common\Brotato",
    os.path.expandvars(r"%ProgramFiles(x86)%\Steam\steamapps\common\Brotato"),
    os.path.expandvars(r"%ProgramFiles%\Steam\steamapps\common\Brotato"),
]


def find_pck(game_dir):
    """在若干常见布局里找 Brotato.pck；找不到就浅层递归搜一遍。"""
    cands = [
        os.path.join(game_dir, "common", "Brotato", "Brotato.pck"),
        os.path.join(game_dir, "Brotato", "common", "Brotato", "Brotato.pck"),
        os.path.join(game_dir, "Brotato.pck"),
        os.path.join(game_dir, "common", "Brotato.pck"),
    ]
    for c in cands:
        if os.path.isfile(c):
            return c
    for root, dirs, files in os.walk(game_dir):
        if root[len(game_dir):].count(os.sep) > 3:
            dirs[:] = []
        if "Brotato.pck" in files:
            return os.path.join(root, "Brotato.pck")
    return None


def find_game_dir(explicit=None):
    if explicit:
        return os.path.abspath(explicit)
    for c in DEFAULT_DIRS:
        if c and os.path.isfile(os.path.join(c, "Brotato.exe")):
            return os.path.abspath(c)
    for c in DEFAULT_DIRS:
        if c and os.path.isdir(c):
            return os.path.abspath(c)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", help="Brotato 安装目录（含 common/Brotato/Brotato.pck 的那个）")
    ap.add_argument("--mod", default="mods-unpacked/Local-Cheat", help="mod 目录")
    ap.add_argument("--no-backup", action="store_true")
    args = ap.parse_args()

    game = find_game_dir(args.game)
    if not game:
        print("找不到 Brotato 安装目录，请用 --game 指定")
        return 1
    pck = find_pck(game)
    if not pck:
        print("在", game, "下找不到 Brotato.pck")
        print("请用 --game 指定游戏目录，例如：")
        print(r'    python tools\pck_patch.py --game "D:\game\Brotato"')
        return 1
    print("目标 pck:", pck)

    mod_dir = os.path.abspath(args.mod)
    if not os.path.isdir(mod_dir):
        print("找不到 mod 目录:", mod_dir)
        return 1
    mod_name = os.path.basename(mod_dir)

    new_files = []
    for root, _dirs, files in os.walk(mod_dir):
        for f in files:
            disk = os.path.join(root, f)
            rel = os.path.relpath(disk, mod_dir).replace(os.sep, "/")
            arc = "res://mods-unpacked/%s/%s" % (mod_name, rel)
            new_files.append((arc, disk))

    data = open(pck, "rb").read()
    entries, table_end = parse_pck(data)
    existing = set(e[0] for e in entries)
    for arc, _ in new_files:
        if arc in existing:
            print("已存在同名文件，跳过:", arc)
    new_files = [(a, d) for a, d in new_files if a not in existing]
    if not new_files:
        print("没有需要写入的新文件（可能已经打过补丁）")
        return 0

    if not args.no_backup and not os.path.exists(pck + ".bak"):
        shutil.copy2(pck, pck + ".bak")
        print("已备份原文件:", pck + ".bak")

    payload = []
    for arc, disk in new_files:
        content = open(disk, "rb").read()
        payload.append([arc, encode_path(arc), 0, len(content),
                        hashlib.md5(content).digest(), content])

    old_table_size = table_end - HEADER_SIZE
    new_table_size = old_table_size + sum(4 + len(e[1]) + 8 + 8 + 16 for e in payload)
    delta = new_table_size - old_table_size
    old_data_len = len(data) - table_end

    cur = HEADER_SIZE + new_table_size + old_data_len
    for e in payload:
        e[2] = cur
        cur += len(e[5])

    tmp = pck + ".new"
    with open(tmp, "wb") as out:
        out.write(data[:COUNT_OFFSET])
        out.write(struct.pack("<i", len(entries) + len(payload)))
        out.write(data[COUNT_OFFSET + 4:HEADER_SIZE])
        for path, raw, o, s, md5 in entries:
            out.write(struct.pack("<i", len(raw)))
            out.write(raw)
            out.write(struct.pack("<q", o + delta))
            out.write(struct.pack("<q", s))
            out.write(md5)
        for path, raw, o, s, md5, content in payload:
            out.write(struct.pack("<i", len(raw)))
            out.write(raw)
            out.write(struct.pack("<q", o))
            out.write(struct.pack("<q", s))
            out.write(md5)
        out.write(data[table_end:])
        for path, raw, o, s, md5, content in payload:
            out.write(content)
    os.replace(tmp, pck)

    print("已写入 %d 个文件到 %s" % (len(payload), pck))
    for e in payload:
        print("   +", e[0])
    print("原文件备份:", pck + ".bak")
    print("还原方法:  copy /Y \"%s.bak\" \"%s\"" % (pck, pck))
    return 0


if __name__ == "__main__":
    sys.exit(main())
