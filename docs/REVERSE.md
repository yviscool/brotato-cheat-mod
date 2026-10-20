# 逆向笔记（做这个 Mod 踩过的坑）

这份笔记记录了把 Mod 塞进 Brotato 1.1.x 并让它真正生效所需的关键知识，
全部来自对本机 `Brotato.pck` 的实测。

---

## 1. Brotato.pck 的二进制格式

实测可解析（Godot 3.x 的 PCK，路径按 4 字节对齐）：

```
0x00  char[4] "GDPC"
0x04  u32  pack_version   = 1
0x08  u32  ver_major      = 3
0x0C  u32  ver_minor      = 7
0x10  u32  pack_flags     = 0
0x14  u64  file_base      = 0      (偏移是绝对的)
0x54  u32  file_count             <-- 文件表条目数
0x58  file table:
         u32  path_len
         bytes path        (path_len 字节，含结尾 \0，末尾按 4 字节补 \0)
         u64  offset
         u64  size
         u8[16] md5        (文件内容的 MD5，Godot 端不校验，但保持正确更保险)
0x58+table_size → 所有文件数据（紧跟文件表）
```

要点：

* 路径长度 = `len(path) + 1`，再向上取整到 4 的倍数
* 文件表里的 offset 是**相对文件开头的绝对偏移**
* 追加文件时：文件表变长 → 旧文件 offset 整体平移 → 新数据追加到文件末尾
* MD5 逐文件核对过，100% 吻合

解析脚本见 `tools/pck_patch.py`。

## 2. 这版 Godot 的「老 API」陷阱

Brotato 1.1.x 用的是自编译的 Godot **3.7.dev**，但 Control 的脚本属性名是**老版本**的：

| 想用的 | 这版实际是 | 写错的后果 |
|---|---|---|
| `node.position` | `node.rect_position` | **静默失效**（不报错，UI 停在 0,0） |
| `node.size` | `node.rect_size` | 同上 |
| `node.custom_minimum_size` | `node.rect_min_size` | 同上 |

其它踩到的：

* `String.contains()` 不存在 → 用 `find(x) != -1`
* `Variant` 不能当类型标注 → `var x = expr`（不要 `:=`）
* `StyleBoxFlat.set_border_width_all()` / `set_corner_radius_all()` 不存在 → 逐个设 `border_width_*` / `corner_radius_*`
* `Vector2.round()` 不存在 → `floor()` / `round()`

**教训：先 `get_property_list()` 打出可用属性名，再动手写。**

## 3. CanvasLayer 里的 Control 尺寸是 0

把 Control 挂在自建 CanvasLayer 下时，它的父级区域是 0×0，
`size` 赋值会被引擎按「锚点相同 ⇒ 尺寸由 offset 决定」的规则重置回 0。

解法（`mod_main.gd` 里的 `_set_rect`）：

```gdscript
func _set_rect(c: Control, pos: Vector2, size: Vector2) -> void:
    c.rect_position = pos
    c.rect_size = size
```

居中：

```gdscript
var ms := _panel.get_combined_minimum_size()
_set_rect(_panel, Vector2(floor((vs.x - ms.x) * 0.5), floor((vs.y - ms.y) * 0.5)), ms)
```

## 4. 让 Mod 在「ModLoader 被禁用」时也能加载

ModLoader 有时会被游戏自己关掉：

```
INFO ModLoader:Loader: Mods are currently disabled
```

于是尝试用 Godot 的 `override.cfg` 把脚本注册成 autoload 来绕过：

```ini
[autoload]
Local-Cheat="*res://mods-unpacked/Local-Cheat/mod_main.gd"
```

**结论：会导致进游戏卡死** —— override.cfg 会让 ModLoader 变成最后一个 autoload，
破坏了游戏原本的初始化顺序。已放弃，最终只用 ModLoader 加载。

## 5. 游戏里真正可用的接口（运行时 dump 得到）

`RunData`（autoload）关键方法/属性：

```
金币    get_player_gold(i) / add_gold(v, i) / remove_gold(v, i)
经验    add_xp(v, i) / get_player_xp(i) / get_player_level(i)
属性    add_stat(key, v[, i]) / remove_stat(key, v) / get_stat(key)
效果    get_player_effects(i) -> Dictionary
血量    get_player_current_health(i) / get_player_max_health(i)
波次    current_wave / wave_timer / instant_waves / on_wave_end
无敌    invulnerable
小工具  get_player_count() / get_player_items(i) / get_player_weapons(i)
```

`Player` 节点（脚本 `res://entities/units/player/player.gd`）关键成员：

```
current_stats / max_stats        -> LiveStats（含 health）
disable_hurtbox() / enable_hurtbox()
_invincibility_timer              -> Timer（无敌倒计时）
_lose_health_timer                -> Timer（持续掉血：毒/拷问）
take_damage(value, hitbox, dodgeable, armor_applied, ...)
```

### 三个「看起来能用其实不行」的写法

1. **`RunData.invulnerable = true` 并不无敌**
   1.0 版本源码里玩家的 `take_damage` 会判断它，但 1.1.x 实测无效。
   真正管用的是**关掉受击框**：`player.disable_hurtbox()`，
   同时要 `stop()` 掉 `_invincibility_timer`（否则它会把受击框重新打开）。

2. **`instant_waves` 不能立刻结束当前波**
   它只在**下一波开始时**生效：

   ```gdscript
   _wave_timer.wait_time = 1 if RunData.instant_waves else current_wave_data.wave_duration
   ```

   想立刻结算当前波，要让 `RunData.wave_timer` 马上超时：

   ```gdscript
   var t = RunData.get("wave_timer")
   t.set("wait_time", 0.15)
   t.call("start")
   ```

3. **杀光敌人不会自动结算**
   波次结束靠计时器超时，不是靠敌人数量。

## 6. 找节点的坑

* `find_children("*", "Player", ...)` 找不到玩家 —— 全局类名对不上。
  可靠做法是按**脚本路径**判断：

  ```gdscript
  var sc: Object = n.get_script()
  if str(sc.resource_path).find("/units/player/") != -1: ...
  ```

* 敌人同理：`/enemies/` 或 `enemy.gd`。
* 场景里的实体都在 `Entities` 容器（main.tscn 的 YSort 节点）下，先找它再遍历，比全树 `find_children` 快得多。

## 7. 存档结构

`%appdata%\Brotato\<steamid>\save_v3_0.json`：

```json
{
  "characters_unlocked": [哈希...],
  "items_unlocked": [哈希...],
  "weapons_unlocked": [哈希...],
  "upgrades_unlocked": [哈希...],
  "consumables_unlocked": [哈希...],
  "difficulties_unlocked": [{"character_id": "...", "zones_difficulty_info": [...]}],
  "challenges_completed": [哈希...],
  "data": { "is_unlock_all_save": 0, ... }
}
```

id 是 djb2 哈希：

```python
def h(s):
    v = 5381
    for c in s.encode():
        v = ((v * 33) + c) & 0xFFFFFFFF
    return v
```

用这个算法把 pck 里各 `.tres` 的 `my_id` 哈希写进去，就能全解锁（实测 100% 匹配）。

## 8. 调试方法论

* 自己的日志写 `user://Local-Cheat.log`（≈ `%appdata%\Brotato\Local-Cheat.log`），
  **不会被游戏日志轮转覆盖**，比 `godot.log` 好用。
* 用 `print()` 打进 `godot.log` 也能看到，但会被下一局覆盖。
* 拿不准 API 时，先把 `get_method_list()` / `get_property_list()` 打到日志里，
  **不要靠猜** —— 这一条把整个开发时间从「几十次试错」压到了「两三轮」。
