# 安装与排错详解

## 0. 环境要求

* Brotato **1.1.x**（`Brotato.pck` 里 `Brotato v1.1.15.4` 这类版本）
* Windows + Python 3.8+（只用标准库，无需 pip）
* 游戏目录形如：

```
D:\game\Brotato\
├── Brotato.exe                     ← 启动器（请用它启动，才能用你的存档）
└── Brotato\common\Brotato\
    ├── Brotato.exe
    ├── Brotato.pck                 ← 我们要往里写东西的文件
    └── BrotatoAbyssalTerrors.pck
```

## 1. 方式 A：写进 pck（推荐）

```bat
python tools\pck_patch.py --game "D:\game\Brotato"
```

脚本会自己找 `common\Brotato\Brotato.pck`，找不到时可以用 `--game` 指定。

**它做了什么**

1. 读出 pck 的文件表（路径按 4 字节对齐、offset/size 各 8 字节、MD5 16 字节）
2. 把 `mods-unpacked/Local-Cheat/` 下的文件登记为 `res://mods-unpacked/Local-Cheat/*`
3. 文件表变长 ⇒ 原有文件在 pck 里的偏移整体后移 ⇒ 全部重写
4. 新文件数据追加到 pck 末尾
5. 校验每个文件的 MD5，原文件自动备份为 `Brotato.pck.bak`

**还原**

```bat
copy /Y "D:\game\Brotato\Brotato\common\Brotato\Brotato.pck.bak" "D:\game\Brotato\Brotato\common\Brotato\Brotato.pck"
```

> Steam 若校验文件重新下载 pck，mod 会失效，重跑一次脚本即可。

## 2. 方式 B：ModLoader zip

打好的 `Local-Cheat.zip` 放到：

```
<游戏目录>\mods\Local-Cheat.zip
```

或者创意工坊目录：

```
<游戏目录>\workshop\content\1942280\<任意数字目录>\Local-Cheat.zip
```

zip 内部结构（Godot ModLoader 要求）：

```
mods-unpacked/Local-Cheat/manifest.json
mods-unpacked/Local-Cheat/mod_main.gd
```

用 `python tools\build_zip.py` 生成。

**为什么有些环境加载不了**
ModLoader 在 Steam 环境下会用 Steam UGC API 拉取「已订阅」的作品；模拟器/离线环境下这个 API 不可用：

```
ERROR: UGC class not found, Steam may not be initialized: getSubscribedItems
INFO  ModLoader:Loader: No zipped mods found
```

看到这两行就说明 **创意工坊渠道不可用**，请改用方式 A（方式 A 不依赖 Steam）。

## 3. 验证是否装上

启动游戏，看日志：

```
%appdata%\Brotato\logs\modloader.log
```

成功时会出现：

```
SUCCESS ModLoader:Loader: DONE: Setup 1 mods
INFO    ModLoader:ModData: Loading mod_manifest (manifest.json) for -> Local-Cheat
INFO    ModLoader:Loader: Initializing -> Local-Cheat
```

以及 mod 自己的日志：

```
%appdata%\Brotato\Local-Cheat.log
[Local-Cheat] loaded | F2 菜单 | F3 金币 | F4 无敌 | F5 清怪 | F6 自动清怪 | ESC 关闭
```

游戏里按 `F2` 就能看到面板。

## 4. 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| F2 没反应 | 看 `modloader.log`：如果是 `Mods are currently disabled`，关掉游戏重开一次（游戏重启自身时会临时禁用 mod） |
| 菜单跑到屏幕左上角 | 这版 Godot 要用 `rect_position`/`rect_size`，不是 `position`/`size` |
| 进游戏卡死 | 检查是不是用了 `override.cfg` autoload 方案，会破坏 autoload 顺序 |
| 存档变空 | 用 `D:\game\Brotato\Brotato.exe`（启动器）启动才会用 Steam 存档；直接跑 `common\Brotato\Brotato.exe` 用的是 `user://user/` 另一套存档 |
| 血量/属性异常 | 菜单里点「全部关闭」可一键还原（生命上限、吸血、攻速都会还原） |

## 5. 顺带一提：解锁全部内容

Brotato 存档里的解锁项存的是 id 的 djb2 哈希：

```python
def h(s):
    v = 5381
    for c in s.encode():
        v = ((v * 33) + c) & 0xFFFFFFFF
    return v
```

用这个哈希把角色/道具/武器/升级的 id 写进 `save_v3_0.json` 的
`characters_unlocked` / `items_unlocked` / `weapons_unlocked` / `upgrades_unlocked` 即可全解锁。
（id 列表可以直接从 `Brotato.pck` 里各 `.tres` 的 `my_id` 提取。）
