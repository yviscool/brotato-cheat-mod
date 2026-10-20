# 《土豆兄弟修改器开发手记》

### 从零理解 Godot 游戏 Mod、Brotato 内部结构，以及我们这个作弊 Mod 是怎么跑起来的

> 面向读者：会一点编程、想搞懂「游戏修改器/Mod 到底是怎么做出来的」的开发者。
> 阅读方式：第 1–3 章是背景知识（可以当教科书看），第 4–6 章是本项目的实现细节，
> 第 7–9 章是方法论与踩坑清单，第 10 章教你自己动手加功能。

---

## 第 0 章 写在前面

### 0.1 这本书想解决什么问题

你可能有过这样的经历：想在某个游戏里加个无敌、无限金币，或者加一把自己的武器，
于是去网上搜「XX 修改器」，下载到一个 exe，双击，要么没反应，要么要你填一堆奇怪的
东西，最后还不知道它到底改了什么。

这本书想让你明白的是：

1. **游戏是可以被「合法地」改造的**，而且游戏开发商自己通常也提供了官方途径（官方 Modding Guide）。
2. 改造的技术路径有哪些、各自的代价与风险。
3. 我们这个 Brotato Mod 具体是怎么写出来的，每一行代码背后依赖了什么。
4. 遇到「按钮没反应」「界面跑到左上角」这类问题时，该怎么系统地排查。

### 0.2 一句话总览：我们到底做了什么

> 我们写了一个 GDScript 脚本（`mod_main.gd`）+ 一份清单（`manifest.json`），
> 用游戏内置的 **Godot Mod Loader** 加载进 `Brotato.pck`，
> 然后在运行时读取游戏自己的数据对象（`RunData`、`Player`），
> 直接把金币、血量、波次这些值改成我们想要的样子，并画了一个中文 UI 面板出来。

拆开看只有三件事：

| 层次 | 做的事 | 用到的技术 |
|---|---|---|
| **加载** | 让游戏执行我们的一段代码 | Godot Mod Loader / PCK 注入 |
| **读写** | 找到游戏运行时里的数据对象并修改 | GDScript 动态调用（`get` / `set` / `call`） |
| **呈现** | 画一个自己的面板、接收按键 | Godot 的 Control / CanvasLayer / InputMap |

### 0.3 术语速查表

| 术语 | 通俗解释 |
|---|---|
| **Godot** | 开源游戏引擎。Brotato 就是用它做的。 |
| **节点 Node** | 游戏里的一个「物件」，可以挂脚本、可以有子节点。 |
| **场景 Scene** | 一棵节点树，保存成 `.tscn` 文件。 |
| **脚本 Script** | 挂在节点上的代码，GDScript 是它的脚本语言。 |
| **GDScript** | Godot 的脚本语言，语法像 Python。 |
| **PCK** | Godot 把整个游戏打包成的「虚拟文件系统」文件（资源包）。 |
| **导出模板 export template** | 编译好的 Godot 运行时（就是 `Brotato.exe`）。 |
| **autoload** | 启动时自动创建、全局唯一的节点（单例）。 |
| **InputMap** | 「按键 → 动作名」的映射表，例如 `ui_cancel` 对应 ESC。 |
| **Theme** | 一套 UI 外观（字体、按钮样式、面板样式）。 |
| **mod loader** | 一个能在运行时把外部代码/资源加载进游戏的框架。 |
| **manifest.json** | Mod Loader 用的清单文件，声明 mod 名字、版本、依赖。 |
| **DLC / 创意工坊** | 官方或玩家发布内容、分发的渠道。 |

---

## 第 1 章 背景：游戏是怎么跑起来的

### 1.1 Godot 引擎的基本模型

Godot 的世界观只有三个概念，记住这三个就够用了：

**场景（Scene）** = 一棵节点树。例如 Brotato 的主场景 `main.tscn`：

```
Main (Node)                     ← 主场景根节点，挂着 main.gd
├── CanvasLayer                 ← 普通 UI 层
├── StatsManager (Node2D)
├── WaveManager (Node2D)
├── EntitySpawner (Node2D)      ← 刷怪器
├── Entities (YSort)            ← 所有实体（玩家、敌人、树）都放这儿
├── PlayerProjectiles (Node2D)
├── EnemyProjectiles (Node2D)
├── fog_viewport (Viewport)
└── UI (CanvasLayer)            ← 菜单 UI 层
```

**节点（Node）** 是最小的单位。每个节点可以：
- 有一个脚本（`.gd`），脚本里定义它的行为（`func`）和状态（`var`）；
- 有子节点；
- 发信号（signal），别人可以连接（connect）它。

**信号（signal）** 是 Godot 的事件机制。例如玩家受伤时会发 `took_damage` 信号，
UI 监听它来更新血条；`RunData` 在金币变化时发 `gold_changed`，商店监听它刷新数字。

```gdscript
# 典型写法：连接信号
RunData.connect("gold_changed", _ui_gold, "on_gold_changed")

# 或者（我们 mod 里用的旧式写法，兼容性最好）
_run_data.connect("gold_changed", self, "_on_gold_changed")
```

### 1.2 导出：exe + pck

Godot 编辑器里写完游戏，点「导出」，会得到至少两个文件：

```
Brotato.exe        ← 导出模板：一个小的 Godot 运行时（39MB）
Brotato.pck        ← 你的整个游戏：所有场景、脚本、贴图、音频、字体
```

运行时 `Brotato.exe` 启动后，会把 `Brotato.pck` 当成一个**只读的虚拟文件系统**挂载成 `res://`。
于是游戏里写 `res://entities/units/player/player.gd` 就能拿到那个脚本。

> **关键点 1**：`res://` 是只读的。游戏运行时不能往里写文件。
> **关键点 2**：但你**可以**在运行时把另一个 `.pck`/`.zip` 叠加挂载上去——
> 这正是 Mod Loader 和我们「改 pck」两种手法的共同基础。

`.pck` 里除了资源，还有编译过的脚本字节码（Godot 3 里是 `.gdc`），所以正常发行版里
你看不到 `.gd` 源码，只有 `.gd.remap`（指向 `.gdc`）和 `.gdc`。

### 1.3 Autoload：游戏里的「全局单例」

Autoload 是在场景树启动前自动创建的节点，任何脚本都能直接按名字访问。
Brotato 1.1.x 的 autoload 列表（我们从 `project.binary` 里 dump 出来的）：

```
CrashReporter, BugReporter, Platform, Keys, ModLoaderStore, ModLoader, Utils,
MenuData, ProgressData, AnnouncementManager, ItemService, SkinManager,
ZoneService, RunData, SoundManager, SoundManager2D, MusicManager, Text,
ChallengeService, InputService, WeaponService, TempStats, LinkedStats,
DebugService, CursorManager, CoopService, FocusEmulatorSignal,
EffectBehaviorService, EntityService, PetService, PopinManager, Streamplay,
UIService, SoundService, OS_Seaven
```

其中对我们最重要的是：

| autoload | 是什么 | 我们用它做什么 |
|---|---|---|
| `RunData` | 一局游戏的所有运行时数据（金币、经验、属性、效果、波次） | 改金币、加经验、改属性、拿波次计时器 |
| `Keys` | 各种 id → 哈希 的映射工具 | 把 `free_rerolls` 这种字符串 id 变成字典键 |
| `ProgressData` | 存档（解锁、成就、统计） | 读取/备份存档 |
| `ModLoader` | 第三方 mod 加载框架本体 | 加载我们的 mod |

### 1.4 InputMap：按键 → 动作

游戏不直接写「按 ESC 就暂停」，而是定义**动作（action）**：

```
input/ui_accept      → Enter / Space
input/ui_cancel      → ESC
input/open_debug_menu→ F2 + Ctrl/Alt/Shift
```

代码里用 `Input.is_action_pressed("ui_cancel")` 判断。
好处是玩家可以自己改键，代码也不用改。

我们 mod 里同时用了两种方式：

```gdscript
# 方式一：判断物理键位（不受玩家改键影响，我们的 F2/F3… 用这个）
if k.scancode == KEY_F2: ...

# 方式二：判断动作（ESC 用这个，语义更准确）
if event.is_action_pressed("ui_cancel"): ...
```

### 1.5 Theme / 字体 / StyleBox：UI 长什么样

Godot 的 UI 外观来自 **Theme**（主题）资源，里面定义：

```
Button/styles/normal     ← 按钮背景
Button/fonts/font        ← 按钮字体
CheckButton/icons/on     ← 勾选框打开时的图
PanelContainer/styles/panel ← 面板背景
default_font              ← 默认字体
```

Brotato 自带一个主题 `res://resources/themes/base_theme.tres`，
里面还带字体 `res://resources/fonts/raw/NotoSansSC-Medium.otf`（中文简体）✓。

所以我们的面板只要 `load()` 这个主题设到自己的 Control 上，
按钮、面板就自动长得跟游戏里一模一样。

> **踩坑**：主题里 `Button/styles/normal` 是「黑色圆角块」，
> 直接用会导致深色面板上按钮「看不见」（黑底黑按钮）。
> 后来我们给按钮单独覆盖了样式（浅灰底 + 白边）。

字体方面，Godot 的 `DynamicFont` 支持**主字体 + 多个 fallback**：

```
font_data  = Anybody-Medium.ttf   ← 拉丁字形
fallback/0 = NotoSansSC-Medium.otf ← 中文
fallback/1 = NotoSansTC-Medium.otf ← 繁体
fallback/2 = NotoSansKR-Medium.otf ← 韩文
fallback/3 = NotoSansJP-Medium.otf ← 日文
```

所以游戏本身的中文界面能正常显示。我们直接复用游戏自带的 `.otf` 即可。

---

## 第 2 章 Brotato 1.1.x 的内部结构

这一章的内容全部来自对本机 `Brotato.pck` 的**实测解析**，不是网上抄的。

### 2.1 版本信息

```
Godot Engine v3.7.dev.custom_build.74e86be54
Brotato v1.1.15.4
```

注意这是**自编译的 Godot 3.7-dev**，它的 Control 脚本属性名是**老版本**的
（`rect_position` 而不是 `position`），这是后面一大半坑的根源。

### 2.2 主场景节点树（`res://main.tscn` 里 dump 出来的）

```
Main (Node)
├── CanvasLayer            ← 普通 UI
├── StatsManager (Node2D)
├── WaveManager (Node2D)
├── EffectsManager (Node2D)
├── FloatingTextManager (Node2D)
├── EntitySpawner (Node2D)  ← 刷怪
├── EffectBehaviors (Node)
├── Camera (Camera2D)
├── Entities (YSort)        ← ★ 玩家/敌人/树都在这里
├── PlayerProjectiles (Node2D)
├── EnemyProjectiles (Node2D)
├── Materials (Node2D)      ← 掉落的金币等
├── Consumables (Node2D)
├── Births (Node2D)
├── fog_viewport (Viewport)
├── WorldUI (CanvasLayer)
├── UI (CanvasLayer)        ← 菜单
├── DamageVignette (ColorRect)
├── DimScreen
└── WaveClearedLabel
```

**`Entities` 这个容器非常关键**：想遍历「场上所有敌人」，直接遍历它的 children 即可，
比全场景 `find_children` 快得多，也不容易误伤。

### 2.3 `RunData`：一局游戏的数据中枢

`RunData` 是我们的主要接口。从运行时 `get_method_list()` dump 出来的关键部分：

```gdscript
# 金币
func get_player_gold(player_index) -> int
func add_gold(value, player_index) -> void
func remove_gold(value, player_index) -> void
func get_player_currency(player_index)
func add_currency(...) / remove_currency(...)

# 经验 / 等级
func add_xp(value, player_index)
func get_player_xp(player_index)
func get_player_level(player_index)
func get_xp_needed(player_index) / get_next_level_xp_needed(...)

# 属性与效果
func add_stat(stat_name: String, value: int[, player_index])
func remove_stat(stat_name: String, value: int)
func get_stat(stat_name: String) -> float
func get_player_effects(player_index) -> Dictionary
func get_player_effect(effect_key, player_index)

# 血量
func get_player_current_health(player_index)
func get_player_max_health(player_index)

# 波次
var current_wave
var wave_timer          ← ★ 波次计时器（跳波用）
var instant_waves       ← ★ 只在下一波生效
var invulnerable        ← ★ 无敌开关（但 1.1.x 不生效，见第 5 章）
var nb_of_waves, current_zone, current_difficulty

# 其它
func get_player_count()
func get_player_items(i) / get_player_items_ref(i)
func get_player_weapons(i) / get_player_weapons_ref(i)
func on_wave_end() / on_wave_start()
func reset_wave_caches() / reset_to_start_wave_state()
```

### 2.4 `Player` 节点：战斗单位

`res://entities/units/player/player.gd`（继承 `unit.gd` → `entity.gd`）。
运行时 dump 出来的关键成员：

```gdscript
var current_stats: LiveStats   # 当前血量等
var max_stats: LiveStats       # 上限
var dead: bool
var player_index: int
var _invincibility_timer: Timer   # ★ 无敌倒计时
var _lose_health_timer: Timer     # ★ 持续掉血（毒/拷问）
var _hurtbox: Area2D               # ★ 受击框

func disable_hurtbox()          # ★ 关掉受击框 = 打不到
func enable_hurtbox()
func take_damage(value, hitbox=null, dodgeable=true, armor_applied=true, ...)
func die(knockback_vector=Vector2.ZERO, p_cleaning_up=false)
func get_iframes()
```

`Entity` 基类还有 `var stats / current_stats / max_stats`，`LiveStats` 里是 `health` 等数值。

### 2.5 一帧内发生了什么

大致循环（主场景 `main.gd` 驱动）：

1. `_wave_timer` 倒计时；每 tick 通过 `WaveManager` → `EntitySpawner` 刷怪（敌人、树、结构）
2. 玩家的 `_physics_process` 处理移动、武器冷却、命中判定
3. 敌人被 `take_damage` 扣血，血 ≤ 0 时走 `die()`，掉落金币（`Materials` 容器）
4. **波次结束的条件是 `_wave_timer` 超时**（不是「敌人清空」）
5. 超时后进入商店（Shop）→ 升级 → 下一波

第 4 点是理解「跳过一波」的关键，后面会展开。

---

## 第 3 章 Mod 系统：Godot Mod Loader 是怎么工作的

### 3.1 它解决什么问题

官方 Modding Guide 的要求是：**不要把改过的原游戏文件发出去**（那是盗版的边界）。
所以需要一个能在运行时把「额外的脚本/资源」塞进游戏、并且能覆盖原脚本的框架。

Brotato 用的就是开源的 **godot-mod-loader**（v6.3.0），仓库：
<https://github.com/GodotModding/godot-mod-loader>

### 3.2 两种加载源

```
1. 本地：<游戏目录>/mods/*.zip
2. 创意工坊：<Steam目录>/steamapps/workshop/content/1942280/<作品ID>/*.zip
```

zip 会被 `ProjectSettings.load_resource_pack()` 叠加挂到 `res://` 上，
所以 zip 内部路径必须写成 `mods-unpacked/<Mod名>/...`。

### 3.3 `manifest.json`

Mod Loader 要求每个 mod 目录里有这个清单：

```json
{
    "name": "Cheat",
    "namespace": "Local",
    "version_number": "1.0.0",
    "description": "中文说明",
    "website_url": "",
    "dependencies": [],
    "extra": {
        "godot": {
            "incompatibilities": [],
            "authors": ["Local"],
            "compatible_mod_loader_version": ["6.3.0"],
            "compatible_game_version": ["1.1.X.X"],
            "optional_dependencies": []
        }
    }
}
```

必填项：`name`、`namespace`、`version_number`、`website_url`、`description`、
`dependencies`、`extra`；`extra.godot` 里必须有 `authors`、
`compatible_mod_loader_version`、`compatible_game_version`。

### 3.4 `mod_main.gd` 的生命周期

Mod Loader 加载完 manifest 后，会实例化 `mod_main.gd`（必须 `extends Node`），
加进场景树，然后：

```
_ready()   ← 我们建 UI 的地方
_process(delta) / _physics_process(delta)  ← 每帧
_input(event) ← 按键
```

也可以通过 `modLoader.install_script_extension("res://xxx/yyy.gd")`
**整体替换**游戏里的某个脚本（我们没用，但这是 Mod Loader 最强的能力）。

### 3.5 选项、用户档案、启用状态

* `options.tres` → 当前生效的配置（enable_mods、日志等级、是否读创意工坊……）
* `user://mod_user_profiles.json` → 记录每个用户启用了哪些 mod

### 3.6 为什么这台机器上创意工坊渠道失效

日志里会看到：

```
ERROR: UGC class not found, Steam may not be initialized: getSubscribedItems
INFO  ModLoader:ThirdParty:Steam: Checking workshop items, with path: ".../workshop/content/1942280"
INFO  ModLoader:ThirdParty:Steam: Checking workshop item path: ".../1942280/local_cheat"
INFO  ModLoader:Loader: No zipped mods found
```

原因：Mod Loader 在 Steam 环境下会用 **Steam UGC API** 拉取「用户已订阅的作品列表」，
只加载其中被订阅的项。你的这份是 **Steam 模拟器/离线版**（`steam_is_online: False`），
UGC API 拿不到东西 → 一个都不加载。

注意日志里明明扫到了目录、却依然 `No zipped mods found` —— 这就是「目录扫到了但列表是空的」的证据。

> **这就是我们后来改用「直接改 pck」的原因**：让 mod 成为游戏资源的一部分，
> 完全不依赖 Mod Loader 的加载决策。

### 3.7 还有一种「绕过」尝试及其失败

Godot 支持在 exe 同目录放 `override.cfg`，可以覆盖项目设置，包括 autoload：

```ini
[autoload]
Local-Cheat="*res://mods-unpacked/Local-Cheat/mod_main.gd"
```

这样脚本就不依赖 Mod Loader 了。但实测会**进游戏卡死**——
因为 override.cfg 的存在会让 Mod Loader 变成最后一个 autoload，
破坏了游戏原本的初始化顺序。**结论：不要在正式方案里用这个。**

---

## 第 4 章 我们的 Mod 的架构

### 4.1 三层结构

```
┌───────────────────────────────────────────────┐
│ 表现层  _build_ui() / _layout() / _update_ui()   │  画面板、刷新状态
│        _input()  收按键                          │
├───────────────────────────────────────────────┤
│ 状态层  infinite_gold / god_mode / ...          │  每个开关一个 bool
│        _on_gold() / _on_god() / ...             │  开关的语义在这里
├───────────────────────────────────────────────┤
│ 应用层  _apply_gold() / _apply_god_mode() ...    │  把状态翻译成对游戏的调用
│        _find_players() / _find_enemies()        │
└───────────────────────────────────────────────┘
```

好处：**状态与副作用分离**。比如「无敌」这个状态，
应用层做的是四件事：关受击框 + 停无敌计时器 + 停掉血计时器 + 保持满血，
而表现层只管画那个开关。

### 4.2 帧循环

```gdscript
func _process(delta):
    _layout()              # 每帧重排 UI（窗口大小会变）
    # toast 淡出计时
    # instant_waves 计时
    if god_mode or huge_hp or auto_heal:
        _apply_god_mode()   # 无敌必须每帧生效（否则受击框会被游戏重新打开）
    _tick += delta
    if _tick < 0.2: return
    _tick = 0.0
    if _menu_open: _update_ui()
    if infinite_gold: _apply_gold()
    ...
```

> **为什么无敌要每帧而金币可以 0.2 秒一次？**
> 无敌靠「关掉受击框」实现，而游戏在某些时机会把它重新打开，
> 所以要每帧压一次；金币只是数值，0.2 秒足够。

### 4.3 UI：为什么手动画布局

Godot 的 Control 有两套布局方式：**容器（Container）** 自动排版，和**锚点（anchor）** 手动定位。

正常情况下你会用 `CenterContainer` 之类的容器来居中。但这里有个坑：

> **CanvasLayer 里的 Control 拿不到正确的父级区域，尺寸会变成 0。**
> 于是容器算出来的「居中位置」也是错的，表现为面板永远贴在左上角。

我们的解法是**完全手动**：自己算位置、自己设尺寸。

```gdscript
func _set_rect(c: Control, pos: Vector2, size: Vector2) -> void:
    c.rect_position = pos
    c.rect_size = size

func _layout() -> void:
    var vs := get_viewport().get_visible_rect().size
    _set_rect(_root, Vector2.ZERO, vs)          # 根节点铺满
    _set_rect(_dim, Vector2.ZERO, vs)           # 半透明遮罩铺满
    var ms := _panel.get_combined_minimum_size() # 面板的最小尺寸（内容决定）
    if ms.y > vs.y - 40.0: ms.y = vs.y - 40.0    # 太高就压缩
    _set_rect(_panel,
        Vector2(floor((vs.x - ms.x) * 0.5), floor((vs.y - ms.y) * 0.5)),
        ms)                                       # ← 居中
    _set_rect(_hint, Vector2(10, vs.y - 30), Vector2(90, 22))   # 左下角小提示
```

注意这里用的是 `rect_position` / `rect_size` 而不是 `position` / `size`——见第 9 章。

### 4.4 输入：怎么抢在游戏之前拿到按键

```gdscript
func _input(event: InputEvent) -> void:
    if not (event is InputEventKey): return
    var k := event as InputEventKey
    if not k.pressed or k.echo: return

    # 菜单开着时，ESC 只关我们的菜单，不触发游戏暂停
    if _menu_open and (_is_key(k, KEY_ESCAPE) or event.is_action_pressed("ui_cancel")):
        _close_menu()
        get_viewport().set_input_as_handled()   # ← 吃掉事件
        return

    if _is_key(k, KEY_F2): ...
```

`set_input_as_handled()` 的作用是**阻止事件继续传播**给游戏的其他节点。
这样按 F2 不会同时触发别的动作，按 ESC 关面板时也不会顺手把游戏暂停了。

`_is_key` 同时兼容两套编码（不同 Godot 版本的 F 键 scancode 不同）：

```gdscript
func _is_key(k: InputEventKey, key: int) -> bool:
    if k.scancode == key or k.physical_scancode == key:
        return true
    var low := key & 0xFFFFFF
    if (k.scancode & 0xFFFFFF) != low: return false
    return (k.scancode >> 24) == 1 or (k.scancode >> 22) == 1
```

### 4.5 数据访问：三种「找东西」的方式

```gdscript
# 1) autoload：最简单，/root/<名字>
var rd := get_node_or_null("/root/RunData")

# 2) 按名字找场景节点
var entities := _find_node_named(get_tree().get_root(), "Entities")

# 3) 按脚本路径判断类型（比 find_children(类型名) 可靠）
func _is_player_node(n) -> bool:
    var sc: Object = n.get_script()
    if sc == null: return false
    return str(sc.resource_path).find("/units/player/") != -1
```

> **坑**：一开始我们用 `find_children("*", "Player", ...)` 找玩家，
> 结果永远 0 个——全局类名和脚本路径对不上。改成按脚本路径判断后立刻正常。

### 4.6 十四个功能逐个拆解

| # | 功能 | 关键调用 | 频率 |
|---|---|---|---|
| 1 | 无限金币 | `RunData.add_gold(999999 - cur, i)` | 0.2s |
| 2 | 无限经验 | `RunData.add_xp(50, i)` | 0.2s |
| 3 | 免费商店 | `add_stat("items_price", -100)` + 玩家效果字典 | 0.2s |
| 4 | 免费刷新 | `add_stat("reroll_price", -100)` + `free_rerolls` 效果 | 0.2s |
| 5 | 无敌 | `disable_hurtbox()` + 停两个 Timer | 每帧 |
| 6 | 自动回满血 | `current_stats.health = max_stats.health` | 每帧 |
| 7 | 生命上限 999999 | `max_stats.health = 999999`（记住原值可还原） | 切换时 |
| 8 | 无限吸血 | `add_stat("stat_lifesteal", 1000)` | 切换时 |
| 9 | 无限冷却 | `add_stat("stat_attack_speed", 1000)` | 切换时 |
| 10 | 自动清怪 | 遍历 `Entities`，逐个 `take_damage(999999)` | 0.2s |
| 11 | 清空本波敌人 | 同上，但手动触发 + 提示 | 按键时 |
| 12 | 立刻结束本波 | `RunData.wave_timer.wait_time = 0.15; start()` | 按键时 |
| 13 | 全部关闭 | 逐个反向操作还原 | 按键时 |
| 14 | 面板开关/状态栏 | 见 4.3 / 4.4 | — |

---

## 第 5 章 深入三个关键机制

### 5.1 无敌：受击框 + 无敌倒计时

**直觉做法**：`RunData.invulnerable = true`。

这是从 Brotato 1.0 的反编译源码里看到的（玩家的 `take_damage` 里会检查它）。
实测在 1.1.15 上**完全无效**——属性确实写进去了（日志里 `invulnerable=True`），但照样掉血。

于是我们把玩家节点的属性全 dump 出来，找到了真正的答案：

```
_invincibility_timer   ← 无敌倒计时器
_lose_health_timer     ← 持续掉血计时器（毒、拷问）
disable_hurtbox()      ← 关掉受击框
```

正确做法（三件套）：

```gdscript
for p in _get_players():
    if p.has_method("disable_hurtbox"):
        p.call("disable_hurtbox")        # ① 打不到
    var inv_t = p.get("_invincibility_timer")
    if inv_t != null and inv_t is Timer:
        inv_t.stop()                     # ② 别让游戏把受击框重新打开
    var lose_t = p.get("_lose_health_timer")
    if lose_t != null and lose_t is Timer:
        lose_t.stop()                     # ③ 别被毒/拷问慢慢磨死
    # ④ 兜底：血量保持满
```

`disable_hurtbox()` 之后，玩家身上那个 `Area2D`（受击框）不再参与碰撞检测，
敌人的子弹打过来根本检测不到玩家。

### 5.2 跳过一波：波次是「计时器超时」结束的

**直觉做法**：把敌人全杀了不就结束了？

不行。反编译 1.0 的 `main.gd` 里能看到：

```gdscript
_wave_timer.wait_time = 1 if RunData.instant_waves else current_wave_data.wave_duration
_wave_timer.start()
```

波次长度由**计时器**决定；`instant_waves` 只是让下一波的计时变成 1 秒，
对当前波无效。而「敌人被打光」并不会触发结算——玩家会站在空场地上干等到计时结束。

正解：让计时器立刻超时，走游戏原本的结算流程。

```gdscript
var t := RunData.get("wave_timer")
t.set("wait_time", 0.15)
t.call("start")
```

游戏会在 0.15 秒后自己触发 `_on_WaveTimer_timeout()`，
然后正常进入商店、结算掉落、准备下一波——所有原版逻辑都还在。

> 这是很典型的一类经验：**修改「状态」不如「触发游戏自己的流程」**。
> 改 `current_wave` 只是改了个数字，而让计时器超时能走完整流程。

### 5.3 属性与效果：`add_stat` 和「玩家效果字典」

Brotato 里玩家的加成分两类：

* **属性（stat）**：百分比修正，例如 `stat_lifesteal`、`stat_attack_speed`、`items_price`。
  通过 `RunData.add_stat("名字", 数值)` 加，通过 `remove_stat` 减。
* **效果（effect）**：条目型加成，例如 `free_rerolls`（免费刷新次数）。
  存在玩家自己的效果字典里，键是 **hash 之后的 id**。

所以「免费刷新」我们同时做了两件事：

```gdscript
# ① 把刷新价格压到 0（属性）
RunData.add_stat("reroll_price", -100)
# ② 把免费次数拉满（效果）
var h = Keys.generate_hash("free_rerolls")
RunData.get_player_effects(i)[h] = 999
```

> **坑**：1.0 的源码里效果字典是用**字符串**做键的，1.1.x 改成了**哈希**。
> 我们写了个兼容函数：先试字符串键，没有就用 `Keys.generate_hash()` 算哈希键。

---

## 第 6 章 存档与「全解锁」

### 6.1 存档在哪

```
%appdata%\Brotato\<SteamID>\save_v3_0.json     ← 启动器启动（Steam 档案）
%appdata%\Brotato\user\save_v3_0.json          ← 直接跑 exe（本地档案）
```

⚠️ **两套存档是分开的**！用错启动方式会看起来「存档丢了」。

### 6.2 存档结构

```json
{
  "characters_unlocked": [哈希...],
  "items_unlocked": [哈希...],
  "weapons_unlocked": [哈希...],
  "upgrades_unlocked": [哈希...],
  "consumables_unlocked": [哈希...],
  "difficulties_unlocked": [{"character_id": "...", "zones_difficulty_info": [...]}],
  "challenges_completed": [哈希...],
  "zones_unlocked": [0, 1, 0, 1],
  "data": { "is_unlock_all_save": 0, "enemies_killed": 0, ... }
}
```

### 6.3 id 是哈希

Brotato 内部用 `Keys.generate_hash(id)` 把字符串 id 转成整数存起来。
反推出算法是经典的 **djb2**：

```python
def h(s):
    v = 5381
    for c in s.encode():
        v = ((v * 33) + c) & 0xFFFFFFFF
    return v
```

验证方法：我们从 pck 里所有 `.tres` 提取 `my_id`（共 64 角色 / 247 道具 / 336 武器…），
用上面的算法算哈希，与你存档里已有的条目求交集 → **100% 匹配**，说明算法正确。

### 6.4 批量解锁

```python
save["characters_unlocked"] = sorted(set(save["characters_unlocked"]) | {h(i) for i in character_ids})
... 其余同理
save["data"]["is_unlock_all_save"] = 1
```

难度解锁是嵌套结构：以现有条目为模板，复制一份、把 `character_id` 换成目标角色、
`max_selectable_difficulty` 设为 6（最高难度）。

> **风险提示**：直接改存档有损坏风险，做之前一定先备份
> （我们留了 `save_v3_0.json.precheat`）。

---

## 第 7 章 直接改 pck：原理与实现

### 7.1 为什么还要改 pck

因为第 3.6 节的原因：创意工坊渠道在这个环境下失效，而本地 `mods/` 目录在
Steam 环境下又不会被 Mod Loader 扫描（它的逻辑是二选一）：

```gdscript
if not ModLoaderStore.ml_options.steam_workshop_enabled:
    # 扫本地 mods 目录
else:
    # 只扫创意工坊
```

所以最稳的办法是：**把 mod 变成游戏资源本身**。

### 7.2 PCK 的二进制格式（实测）

```
0x00  char[4] "GDPC"
0x04  u32  pack_version   = 1
0x08  u32  ver_major      = 3
0x0C  u32  ver_minor      = 7
0x10  u32  pack_flags     = 0
0x14  u64  file_base      = 0        ← 偏移是绝对的
0x54  u32  file_count              ← ★ 文件表条目数在这里（偏移 84）
0x58  文件表（每条）：
         u32  path_len
         bytes path    (path_len 字节，含结尾 \0，末尾按 4 字节补 \0)
         u64  offset   (文件在 pck 中的绝对偏移)
         u64  size
         u8[16] md5    (文件内容的 MD5)
...    紧接着是所有文件数据
```

验证过的三件事：
* 路径长度 = `len(path)+1` 再向上取整到 4 的倍数
* 每个文件的 MD5 与实际内容**完全吻合**
* 第一个文件的数据就在文件表结束之后

### 7.3 追加一个文件要改哪些地方

```
原布局：  [头 84B][文件表 N 条][数据区]
新布局：  [头 84B][文件表 N+2 条][数据区（原样）][新数据 1][新数据 2]
             ↑count+2        ↑表变长
```

于是：
1. 文件表变长 → **所有旧文件的 offset 都要整体后移 `delta`**
2. 新文件的 offset = 新的文件表末尾 + 原数据区长度
3. 新文件的数据追加到 pck 末尾
4. 头部的 `file_count` 加 2
5. 重新计算所有 MD5（Godot 端不校验，但保持正确更保险）

### 7.4 工具代码（`tools/pck_patch.py` 核心）

```python
def parse_pck(data):
    count = struct.unpack("<i", data[COUNT_OFFSET:COUNT_OFFSET+4])[0]
    off = HEADER_SIZE
    entries = []
    for _ in range(count):
        (ln,) = struct.unpack("<i", data[off:off+4]); off += 4
        raw = data[off:off+ln]; off += ln
        path = raw.rstrip(b"\x00").decode("utf-8", "replace")
        (o,) = struct.unpack("<q", data[off:off+8]); off += 8
        (s,) = struct.unpack("<q", data[off:off+8]); off += 8
        md5 = data[off:off+16]; off += 16
        entries.append([path, raw, o, s, md5])
    return entries, off

def encode_path(path):
    b = path.encode("utf-8") + b"\x00"
    while len(b) % 4: b += b"\x00"
    return b
```

写入时：

```python
old_table_size = table_end - HEADER_SIZE
new_table_size = old_table_size + sum(4+len(e[1])+8+8+16 for e in payload)
delta = new_table_size - old_table_size          # ← 旧文件要后移这么多

cur = HEADER_SIZE + new_table_size + (len(data) - table_end)
for e in payload: e[2] = cur; cur += len(e[5])   # ← 新文件的绝对偏移
```

### 7.5 幂等性与备份

* **幂等**：再次执行时先检查 `res://mods-unpacked/Local-Cheat/*` 是否已存在，
  存在就跳过——不会把 pck 搞坏（这点很重要，因为用户可能会重复运行脚本）。
* **备份**：第一次执行自动复制 `Brotato.pck.bak`。
* **还原**：`copy /Y Brotato.pck.bak Brotato.pck`。

### 7.6 为什么不直接把 mod 做成 .pck

理论上可以，但我们的 mod 依赖 Mod Loader 的「mod 目录」约定，
而且 Mod Loader 的加载顺序与 `mod_main.gd` 的实例化时机更合适。
把文件塞进 pck 的 `mods-unpacked/` 目录，正好是 Mod Loader 「unpacked 模式」所期待的路径，
两边都能用。

---

## 第 8 章 逆向方法论（这部分最值钱）

如果上面的内容你只记住一件事，请记住这一章。

### 8.1 三板斧

| 工具 | 作用 | 本项目里的用途 |
|---|---|---|
| **解包 pck** | 把 `.pck` 变成一堆可读文件 | 找 `main.tscn`、`base_theme.tres`、字体、`project.binary` |
| **运行时 dump** | 在游戏里把对象的接口打印出来 | 拿到 `RunData` 的方法清单、`Player` 的属性清单 |
| **参考反编译源码** | 找 1.0 版的解包工程当参考 | 理解波次结算、伤害判定、属性系统的设计意图 |

### 8.2 运行时 dump：最实用的一招

GDScript 里这两个函数能告诉你一个对象「到底能干什么」：

```gdscript
obj.get_method_list()      # 所有方法名 + 参数个数 + 默认参数
obj.get_property_list()    # 所有属性名
obj.get_signal_list()      # 所有信号
```

我们的做法是：在 mod 里加一段「诊断代码」，启动游戏后把清单写进日志：

```gdscript
_log("[dbg] RunData props: " + str(_props(rd)))
_log("[dbg] Player methods: " + str(_method_names(player)))
```

配合 `print()`（会进 `godot.log`）或写文件（更可靠），**两三轮就能把整个游戏的数据面摸清**。

> 反例：我们一开始凭直觉猜「`RunData.invulnerable` 就是无敌开关」，
> 猜「`find_children("*","Player")` 能找到玩家」，都错了。
> **猜 API 是这个项目最大的时间黑洞，dump 一次就全清楚了。**

### 8.3 定位一个功能的思路

以「跳过一波」为例：

1. 先在游戏里找**同类功能**：原版开发者自己做了个调试菜单（`ui/menus/debug/debug_menu.tscn`），
   里面有「Instant Waves」「Go to wave」等按钮 —— 说明官方有现成开关。
2. 解包找 `debug_menu.gd` 的字符串常量，发现有 `%GotoWave_spinbox`、`%instantwave_but`。
3. 但那个菜单在正式版被 gate 掉了（输入动作 `open_debug_menu` 存在却没接上）。
4. 于是去反编译源码里搜 `instant_waves` → 发现它只在**下一波开始时**被读取。
5. 再搜波次结束的入口 → `_wave_timer.wait_time` / `_on_WaveTimer_timeout`。
6. 结论：让 `RunData.wave_timer` 立刻超时。

**这个思路可以复用**：找功能 → 找官方开关 → 读源码确认生效时机 → 用「触发原生流程」代替「改状态」。

### 8.4 静默失败怎么查

Godot 有一个非常坑的特性：**属性名写错不会报错**。
`node.position = v` 在这版引擎里不存在这个属性 → 赋值被静默忽略 → 界面不动，但没有任何日志。

排查顺序：

1. `print()` 打关键变量（位置、尺寸、状态）
2. `get_property_list()` 看这个对象**真的**有哪些属性
3. 看 `godot.log` 里有没有 `SCRIPT ERROR`（有就说明是硬错误）

我们就是靠第 2 步发现 `rect_position` / `rect_position` / `rect_min_size` 的。

### 8.5 日志策略

* `print()` → 进 `godot.log`，但**会被下一局覆盖/轮转**。
* 写文件 → `user://xxx.log`（≈ `%appdata%\Brotato\xxx.log`），**不会被覆盖**。
* 我们两者都用：文件是长期日志，stdout 是即时回显。

---

## 第 9 章 工程实践清单（20 条避坑）

1. **不猜 API**。先 `get_method_list()` / `get_property_list()`。
2. **注意属性名的版本差异**（`position` vs `rect_position`）。
3. **写错属性名 = 静默失败**，务必用日志验证效果。
4. **`String.contains()`、`Variant` 类型标注、`StyleBoxFlat.set_*_all()`** 在这版引擎上不存在。
5. **CanvasLayer 里的 Control 尺寸为 0**，要么手动设 `rect_size`，要么别用 CanvasLayer。
6. **`get_viewport().get_visible_rect().size` 才是「真实分辨率」**，窗口大小和它可能不同（游戏会缩放）。
7. **改游戏存档前一定备份**。
8. **写脚本时优先用「方法」而不是「属性」**：`set_position()` / `set_size()` 跨版本更稳。
9. **不要用 `override.cfg` 改 autoload 顺序**，会卡死。
10. **不要依赖 Steam UGC**（模拟器环境不可用）。
11. **让工具幂等**：重复运行不破坏已有产物。
12. **自动化校验**：注入完立刻跑一遍「文件数 + MD5 全对」的检查。
13. **游戏会自己重启**，导致 mod 时有时无——不要误判成「代码写错了」。
14. **信号记得 `set_input_as_handled()`**，避免和游戏自身快捷键冲突。
15. **每帧执行的操作要轻**（`find_children` 全树遍历很贵，优先用 `Entities` 容器）。
16. **数值型属性用「加/减」成对实现**（`add_stat` / `remove_stat`），否则开关来回切会累积。
17. **记住原值再还原**（我们的 `_orig_hp` 就是干这个的）。
18. **对不确定的 API 写降级分支**（例如 `has_method()` 判断后再调）。
19. **给用户留日志和还原方法**，比「神装」更重要。
20. **写文档**：写下你踩过的坑，下一个你（或别人）会省下几天时间。

---

## 第 10 章 如何自己动手

### 10.1 最小可用 mod

`mods-unpacked/MyMod/manifest.json`：

```json
{
  "name": "MyMod", "namespace": "Me", "version_number": "1.0.0",
  "description": "我的第一个 mod", "website_url": "", "dependencies": [],
  "extra": { "godot": {
    "incompatibilities": [], "authors": ["Me"],
    "compatible_mod_loader_version": ["6.3.0"],
    "compatible_game_version": ["1.1.X.X"], "optional_dependencies": [] } }
}
```

`mods-unpacked/MyMod/mod_main.gd`：

```gdscript
extends Node

func _ready() -> void:
	print("Hello from MyMod!")

func _process(delta: float) -> void:
	pass
```

打包 + 安装：

```bat
python tools\build_zip.py
python tools\pck_patch.py --game "D:\game\Brotato"
```

### 10.2 在我们的框架里加一个新开关（完整示例）

假设你要加「无限回血」：

**第一步**：加状态变量

```gdscript
var infinite_heal := false
```

**第二步**：加 UI 开关（在 `_build_ui` 的 grid 里）

```gdscript
_add_toggle(grid, "heal2", "无限回血", f_body)
```

**第三步**：加处理函数（`_set_toggle` 的 match 里加一条）

```gdscript
"heal2": _on_heal2(value),
```

```gdscript
func _on_heal2(v: bool) -> void:
	infinite_heal = v
	_toast_show("无限回血：开" if v else "无限回血：关")
```

**第四步**：加应用逻辑（每帧执行的部分）

```gdscript
func _apply_infinite_heal() -> void:
	for p in _get_players():
		var st: Object = p.get("current_stats")
		var ms: Object = p.get("max_stats")
		if st != null and ms != null and "health" in st and "health" in ms:
			st.set("health", ms.get("health"))
```

并在 `_process` 里调用（记得加进 `if god_mode or huge_hp or auto_heal:` 那类条件里）。

**第五步**：在 `_update_ui` 里同步开关显示

```gdscript
_tg["heal2"].set_pressed_no_signal(infinite_heal)
```

**第六步**：重新打包 + 注入 + 验证

```bat
python tools\build_zip.py
python tools\pck_patch.py --game "D:\game\Brotato"
:: 启动游戏 → 看 %appdata%\Brotato\Local-Cheat.log
```

### 10.3 常见需求配方

| 需求 | 做法 |
|---|---|
| 无限金币 | `RunData.add_gold(999999 - cur, i)` |
| 无限经验 | `RunData.add_xp(50, i)` |
| 满血 | `player.current_stats.health = player.max_stats.health` |
| 无敌 | `player.disable_hurtbox()` + 停 `_invincibility_timer` |
| 秒杀敌人 | `enemy.take_damage(999999, null, false, false)` |
| 跳波 | `RunData.wave_timer.wait_time = 0.15; start()` |
| 升级属性 | `RunData.add_stat("stat_lifesteal", 1000)` |
| 免费商店 | `RunData.add_stat("items_price", -100)` |
| 免费刷新 | `RunData.add_stat("reroll_price", -100)` + 效果 `free_rerolls` |
| 加速移动 | `RunData.add_stat("stat_speed", 100)` |
| 拾取范围 | `RunData.add_stat("effect_pickup_range", 500)` |
| 解锁内容 | 改存档（见第 6 章） |

---

## 第 11 章 延伸学习与工具链

| 资源 | 用途 |
|---|---|
| Godot 官方文档 https://docs.godotengine.org/3.5/ | 节点、信号、Control 布局、Theme |
| Godot Mod Loader https://github.com/GodotModding/godot-mod-loader | mod 规范、API、Wiki |
| Mod Loader 示例 https://github.com/GodotModding/godot-mod-loader-examples | 最小 mod 模板 |
| Brotato 官方 Modding Guide（创意工坊指南） | 官方推荐的改 mod 方式、如何避免踩版权红线 |
| GDRE Tools https://github.com/GDRETools/gdsdecomp | 反编译 `.pck` 成可读工程（Java 版或独立 exe） |
| Brotato Wiki（brotato.wiki.spellsandguns.com） | 数据表、机制说明 |
| 创意工坊 https://steamcommunity.com/app/1942280/workshop/ | 找现成的 mod 参考实现 |

**给你的下一步建议**：

1. 先玩一遍原版创意工坊的 mod（如「Materials X100」），下载下来看看结构 → 建立直觉。
2. 用 GDRE Tools 反编译一份自己的 `Brotato.pck`，对照本书第 2 章看真实源码。
3. 照着第 10 章加一个自己的功能（比如「自动吃药」）。
4. 想更进一步，就去读 Godot Mod Loader 的 `script_extension` 机制——**它能整体替换游戏脚本**，
   理论上你可以重写整个波次系统、商店系统，而不只是改数值。

---

## 附录 A 我们用到的 API 速查

```gdscript
# —— 引擎 ——
OS.get_executable_path()                     # 自己的 exe 路径
get_tree().get_root()                        # 场景树根
get_viewport().get_visible_rect().size       # 真实分辨率
get_node_or_null("/root/RunData")            # 取 autoload
InputMap.has_action / add_action / action_add_event
Object.get_method_list() / get_property_list() / get_signal_list()
Object.get(prop) / set(prop, v) / call(method, args...) / has_method(m)
Node.find_children(pattern, type, recursive, owned)
Node.find_node / get_node_or_null / get_children / get_script()
Control.rect_position / rect_size / rect_min_size
Control.get_combined_minimum_size()
StyleBoxFlat.bg_color / border_color / border_width_* / corner_radius_*
Theme.add_stylebox_override / add_font_override
DynamicFont.font_data / size
File.open(path, READ|WRITE) / seek_end() / store_line()

# —— 游戏 ——
RunData.add_gold / remove_gold / get_player_gold
RunData.add_xp / get_player_level
RunData.add_stat / remove_stat / get_stat
RunData.get_player_effects(i) -> Dictionary
RunData.get_player_count()
RunData.get_player_current_health / get_player_max_health
RunData.current_wave / wave_timer / instant_waves / invulnerable
Keys.generate_hash(str) -> int
Player.current_stats / max_stats
Player.disable_hurtbox() / enable_hurtbox()
Player._invincibility_timer / _lose_health_timer
Unit.take_damage(value, hitbox, dodgeable, armor_applied, ...)
Unit.die(knockback_vector, p_cleaning_up)
```

## 附录 B PCK 格式速查

```
magic "GDPC" | u32 ver | u32 ver_major | u32 ver_minor | u32 flags | u64 file_base
| (pad) | u32 file_count @0x54 | entries @0x58 | data
entry: u32 path_len | path(padded to 4) | u64 offset | u64 size | u8[16] md5
```

## 附录 C 一句话记忆

* **想改数值** → 找到那个数据对象（autoload / 节点），`get` / `set`。
* **想改流程** → 找到游戏自己的入口（计时器、信号、回调），**触发它**而不是伪造状态。
* **不知道 API** → dump 一下。
* **不知道数据在哪** → 解包 + 看场景树 + 看 `project.binary` 的 autoload 列表。
* **不知道格式** → 十六进制看规律，写个解析器验证。
* **改不动** → 换个层次：mod loader → pck 注入 → 二进制补丁 → 存档修改，总有一层能绕过。

---

*全书完。代码与工具见本仓库 `mods-unpacked/` 与 `tools/`。*
