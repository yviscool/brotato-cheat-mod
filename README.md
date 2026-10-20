# 🥔 Brotato 本地作弊 Mod（Local-Cheat）

> Brotato 1.1.x（Godot 3.6/3.7-dev）的本地作弊 Mod：**无限金币、无敌、免费商店、无限吸血、无限冷却、清怪跳波**，全部通过游戏内置的 ModLoader 加载，中文界面、居中面板、按需开启。

* 游戏本体由 [Blobfish Games](https://store.steampowered.com/app/1942280/Brotato/) 开发，本仓库**只包含我自己写的 Mod 代码**，不含任何游戏资源。
* 仅供单机自用/学习 Godot ModLoader 与游戏逆向，感谢官方公开的 [Modding Guide](https://steamcommunity.com/sharedfiles/filedetails/?id=2931079751)。

---

## ✨ 功能一览

| 分类 | 功能 | 说明 |
|---|---|---|
| 资源 | 无限金币 | 每 0.2s 把金币补到 999999 |
| 资源 | 无限经验 | 持续加经验，自动升级 |
| 资源 | 免费商店 | 商店里所有商品价格清零（含按钮显示） |
| 资源 | 免费刷新 | 商店刷新次数拉满、刷新价格归零（按玩家逐个生效） |
| 战斗 | 无敌模式 | 关闭受击框 + 停掉无敌倒计时/持续掉血计时器 |
| 战斗 | 自动回满血 | 血量每帧保持满 |
| 战斗 | 生命上限 999999 | 可一键还原成原值 |
| 战斗 | 无限吸血 | 吸血属性 +1000% |
| 战斗 | 无限冷却 | 攻速属性 +1000%（等于没有冷却） |
| 战斗 | 自动清怪 | 每 0.2s 自动秒掉场上所有敌人 |
| 操作 | 清空本波敌人 | 立刻把本波敌人全部打死 |
| 操作 | 立刻结束本波 | 让本波计时器马上超时，走游戏原本的结算流程 |
| 操作 | 全部关闭 | 一键恢复原状（含属性还原） |

面板顶部实时显示 **金币 / 波次 / 等级 / 血量**。

## ⌨️ 快捷键

| 按键 | 功能 |
|---|---|
| `F2` | 打开 / 关闭作弊菜单（也可点屏幕左下角「F2 作弊」） |
| `ESC` | 关闭作弊菜单（会吃掉事件，不会同时触发游戏暂停） |
| `F3` | 无限金币 开/关 |
| `F4` | 无敌 开/关 |
| `F5` | 清空本波敌人 |
| `F6` | 自动清怪 开/关 |

> 游戏用键盘 `1`~`4` 选角色、`空格` 等操作，这些都没有冲突；`F2`/`ESC` 在原版里没有绑定功能。
> 按键是用 **轮询 `Input.is_key_pressed()`** 实现的（不是事件回调），
> 所以不受游戏自身快捷键或事件传播顺序影响。

---

## 📦 安装

### 方式 A：直接写进游戏 pck（推荐，稳）

不需要装创意工坊、不依赖 Steam API，任何版本都能用。

```bat
:: 1. 备份（脚本也会自动备份一次）
copy /Y "D:\game\Brotato\Brotato\common\Brotato\Brotato.pck" "Brotato.pck.bak"

:: 2. 打补丁（把本仓库的 mod 写进 pck）
python tools\pck_patch.py --game "D:\game\Brotato"

:: 3. 启动游戏，按 F2 打开菜单
```

`tools/pck_patch.py` 会：

1. 解析 `Brotato.pck` 的文件表（路径 4 字节对齐 + 偏移/大小 + MD5）
2. 把 `mods-unpacked/Local-Cheat/` 里的文件追加成 `res://mods-unpacked/Local-Cheat/*`
3. 重新计算文件表与所有文件的偏移，校验 MD5
4. 写出新 pck（原文件自动备份为 `Brotato.pck.bak`）
5. **顺带写一份 `override.cfg`**，把 mod 注册成 autoload

> 第 5 步很关键：Steam 模拟器/离线环境下，游戏自己重启后的那个实例会
> 把 ModLoader 关掉（`Mods are currently disabled`），创意工坊和本地 zip 都加载不了。
> 注册成 autoload 后，**无论 ModLoader 是否被禁用，mod 一定会加载**。
> 删掉 `override.cfg` 即可回到纯 ModLoader 模式。

**还原**：`copy /Y Brotato.pck.bak Brotato.pck`

### 方式 B：ModLoader 创意工坊 / 本地 zip

把 `Local-Cheat.zip` 放到以下任一位置：

```
<游戏目录>\mods\Local-Cheat.zip
<游戏目录>\workshop\content\1942280\<任意数字目录>\Local-Cheat.zip
```

zip 内部结构必须是：

```
mods-unpacked/Local-Cheat/manifest.json
mods-unpacked/Local-Cheat/mod_main.gd
```

> ⚠️ 部分「Steam 模拟器/绿色版」环境下 Steam UGC API 不可用
> （日志里会出现 `UGC class not found, Steam may not be initialized: getSubscribedItems`），
> 此时创意工坊渠道的 mod **不会被加载**，请改用方式 A。

---

## 🔧 从源码构建

```bat
python tools\build_zip.py            :: 生成 dist\Local-Cheat.zip
python tools\pck_patch.py            :: 安装到本机 Brotato
```

## 📄 日志

Mod 会把日志写到（不会被游戏轮转覆盖，比 `godot.log` 好用）：

```
%appdata%\Brotato\Local-Cheat.log
```

排查问题建议看两个：

```
%appdata%\Brotato\Local-Cheat.log     :: mod 自己的日志
%appdata%\Brotato\logs\modloader.log   :: ModLoader 日志（看 mod 有没有被加载）
```

---

## 📖 想系统学习？

**[《土豆兄弟修改器开发手记》](docs/BOOK.md)** —— 11 章 + 3 附录，从 Godot 引擎基础、
Brotato 内部结构、Mod Loader 原理，到我们每个功能的实现、PCK 注入原理、
逆向方法论、20 条避坑清单，以及「如何自己加一个新功能」的完整示例。

## 📂 目录结构

```
.
├── mods-unpacked/Local-Cheat/
│   ├── manifest.json      # ModLoader 的 manifest（name/namespace/version…）
│   └── mod_main.gd        # 全部功能代码
├── tools/
│   ├── pck_patch.py       # 把 mod 写进 Brotato.pck
│   └── build_zip.py       # 打包成 ModLoader zip
├── docs/
│   ├── BOOK.md            # ★《土豆兄弟修改器开发手记》完整教程（11 章 + 3 附录）
│   ├── LESSONS.md         # ★ 后期踩坑与最终方案（12 章，血泪史）
│   ├── INSTALL.md         # 详细安装与排错
│   └── REVERSE.md         # 逆向笔记（PCK 格式 / Godot 老 API / 关键接口）
├── README.md
└── LICENSE
```

## ⚠️ 已知问题

* **进游戏卡死**：不要用 `override.cfg` 把脚本注册成 autoload，会改变游戏 autoload 顺序导致卡死。
* **F2 偶尔没反应**：那次启动 ModLoader 被游戏自己禁用了（`Mods are currently disabled`），重开一次即可。
* **UI 位置**：这版 Godot 是老 API，必须用 `rect_position` / `rect_size` / `rect_min_size`；写 `position` / `size` 会被静默忽略。

## 📜 License

MIT —— 见 [LICENSE](LICENSE)。

游戏及游戏内资源版权归 Blobfish Games 所有，本项目与之无关。
