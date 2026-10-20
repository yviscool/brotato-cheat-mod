# 第 12 章 后期踩坑与最终方案（这一章是「血泪史」）

前面 11 章讲的是「怎么做」，这一章讲的是「做不出来的时候怎么办」——
我们在这个项目最后阶段踩的 6 个坑，以及最终沉淀下来的方案。

---

## 12.1 GDScript 是「严格模式」，类型推断失败会直接编译失败

这版引擎对 `:=` 的类型推断很严格：**右值类型是 Variant 时，编译直接报错**。

```gdscript
var key := it.get_instance_id()      # ❌ it 是 Variant → Parse Error
var key =  it.get_instance_id()      # ✅ 用普通 = 就行

var x := obj.get("some_prop")        # ❌ 同上
var x =  obj.get("some_prop")        # ✅
```

> 这个报错在日志里长这样：
> `SCRIPT ERROR: Parse Error: The assigned value doesn't have a set type; the variable type can't be inferred.`
>
> **而且它会让整个 mod 加载失败**（脚本没编译过 → 不会执行 → 菜单不出来 → 看起来像「F2 没反应」）。
> 排查 F2 失效时，**第一件事永远是看 `godot.log` 里有没有 Parse Error**。

### 12.1.1 我们踩过的最蠢的一次

我们用 python 做「字符串替换」来改脚本，结果替换区间把一个函数定义（`_find_shops()`）一起删掉了，
而调用它的地方还在 → 运行时报「函数不存在」。

**教训**：不要用脆弱的字符串替换改代码。要么整份重写，要么改完立刻做静态检查：

```python
defs  = set(re.findall(r'^func (_[A-Za-z0-9_]+)\s*\(', s, re.M))
calls = set(re.findall(r'(?<![\w.])(_[A-Za-z][A-Za-z0-9_]*)\s*\(', s))
missing = sorted(c for c in calls if c not in defs)
assert not missing, missing      # ← 提交前跑一遍
```

这个 10 行的检查，后来救了我们很多次。

---

## 12.2 输入事件会被游戏吃掉 → 改成「轮询按键状态」

一开始我们用 `func _input(event)` 接收按键。在大部分时候没问题，
但会出现「时好时坏、明明日志里有加载成功但菜单就是不出来」的情况。

原因：Godot 的事件传播是**深度优先、先子节点后父节点**，
游戏主场景里的节点可能比我们的 autoload 更早拿到事件，
一旦它们调用了 `set_input_as_handled()`，我们就再也收不到了。

**最终方案：不收事件，直接轮询按键的当前状态。**

```gdscript
const KEY_MAP := [[KEY_F2, "menu"], [KEY_F3, "gold"], ...]
var _key_down := {}

func _poll_keys() -> void:
	for entry in KEY_MAP:
		var code = entry[0]
		var id   = str(entry[1])
		var down = Input.is_key_pressed(code)      # ← 直接问「这个键现在按着吗」
		var was  = bool(_key_down.get(id, false))
		_key_down[id] = down
		if down and not was:                        # 上升沿 = 只触发一次
			_handle_key_id(id)
```

优点：
* 不受事件传播顺序影响
* 不受 InputMap 被改键影响
* 不会和游戏的快捷键冲突（`set_input_as_handled()` 都不需要了）
* 代价：每帧多几次 `Input.is_key_pressed` 调用，可以忽略

> **教训**：当「事件收不到」时，先想「是不是被别人消费了」，
> 然后考虑「能不能不靠事件」（轮询状态、轮询数据）。

---

## 12.3 ModLoader 会被游戏自己关掉 → 最终方案：override.cfg 注册 autoload

日志里经常出现：

```
INFO ModLoader:Loader: Mods are currently disabled
```

原因：这台机器是 **Steam 模拟器/离线版**，游戏在「用 Steam 重启自己」之后的那个实例里，
把 ModLoader 关掉了（大概是怕 mod 影响启动）。于是**创意工坊和本地 zip 两条路都失效**。

我们先试过 `override.cfg` 的 autoload 方案，当时判断「会导致卡死」——**那个结论是错的**，
因为那次 autoload 的脚本本身有编译错误（`String.contains()` 不存在），
脚本没编译过 → autoload 报错 → 游戏卡住。**卡死的锅在脚本，不在机制。**

修好脚本后再上 autoload，一切正常：

```ini
; D:\game\Brotato\Brotato\common\Brotato\override.cfg
[autoload]

Local-Cheat="*res://mods-unpacked/Local-Cheat/mod_main.gd"
```

配合「同一个脚本可能被加载两次（autoload + ModLoader）」的守卫：

```gdscript
var tree = get_tree()
if tree.has_meta("local_cheat_built"):
	return                      # 已经有实例了，别再建一份 UI
tree.set_meta("local_cheat_built", true)
```

### 12.3.1 现在的加载链路

```
启动游戏
  └─ Godot 读取 override.cfg → 把 mod_main.gd 注册成 autoload
       └─ autoload 实例 _ready() → 建 UI（设置 meta 标记）
            └─ ModLoader 若启用，也会加载同一脚本 → 发现 meta 已存在 → 直接 return
```

结果：**无论 ModLoader 是否被禁用，F2 菜单都在**。

> **教训**：一个「机制看起来有风险」的方案，可能只是被你代码里的 bug 冤枉了。
> 当时应该先修脚本、再验证机制，而不是直接否定机制。

---

## 12.4 商店价格是「按玩家分的数组」，不是标量

这是「免费商店 / 免费刷新」死活不生效的真正原因。

我们最初从 Brotato 1.0 的反编译源码里读到：

```gdscript
var _reroll_price: = 0
var _free_rerolls: = 0
```

于是按标量写：`shop.set("_reroll_price", 0)`。**在 1.1.15 上完全无效。**

运行时 dump 商店节点才发现：

```
[shop] node=/root/Shop visible=True reroll_price=[59, 0, 0, 0] free_rerolls=[0, 0, 0, 0]
```

—— 1.1.x 支持 4 人联机，所以这些字段变成了**每个玩家一个值的数组**。

### 12.4.1 通用写法：数组就逐个写，标量就直接赋值

```gdscript
func _set_shop_field(obj, field: String, value) -> void:
	var cur = obj.get(field)
	if typeof(cur) == TYPE_ARRAY:
		for i in range(cur.size()):
			cur[i] = value
	else:
		obj.set(field, value)
```

### 12.4.2 免费刷新要做的三件事

```gdscript
_set_shop_field(shop, "_free_rerolls", 999)   # 免费次数拉满
_set_shop_field(shop, "_reroll_price", 0)      # 刷新价清零
shop.set("_has_bonus_free_reroll", true)       # 顺便打开 bonus 免费标记
if shop.has_method("set_reroll_button_price"):
	shop.call("set_reroll_button_price")        # 让按钮上的显示同步成 0
```

### 12.4.3 免费商店（商品价格）

商品价格在 `ShopItem.value` 上（同样可能是数组）：

```gdscript
it.set("value", 0)                              # 实际扣费金额
var btn = it.get("_button")
if btn.has_method("set_value"):
	btn.call("set_value", 0)                   # 同步按钮上显示的价格
```

> **教训**：**版本差异是「同名不同型」的陷阱**。
> 1.0 是标量，1.1.x 是数组；字段名一模一样。
> 所以任何「从旧版源码抄来的赋值」都要先在运行时验证一次：
> `log(typeof(obj.get(field)))` + `log(obj.get(field))`。

---

## 12.5 调试全链路：埋点要埋到「用户能看见的最后一环」

最后那几天我们靠一条日志定位了所有问题，日志长这样：

```
[key] F2 菜单 -> True                                  ← ① 按键被收到
[toggle] id=reroll pressed=True                        ← ② 开关被点到
[shop] node=/root/Shop visible=True                    ← ③ 找到商店节点
[shop] price [0,0,0,0] -> [0,0,0,0] | free [999,...]   ← ④ 改前 → 改后
```

**每一环都要留痕**，否则你只知道「没生效」，不知道断在哪一环。

我们踩过的具体例子：
* 断在 ①：事件被游戏吃掉 → 改轮询
* 断在 ②：信号绑定参数顺序反了（Godot 3 里 `connect(..., binds)` 的绑定参数顺序在不同版本不一致）→ 写成两种顺序都能兼容
* 断在 ③：脚本没编译（Parse Error）→ 一切都没执行
* 断在 ④：字段是数组不是标量

---

## 12.6 最后的方案清单（当前版本）

| 问题 | 最终解法 |
|---|---|
| 菜单不居中 | 手动画布局：`rect_position` / `rect_size`（不用 `position`/`size`） |
| F2 时好时坏 | 改用 `Input.is_key_pressed()` 轮询 + `override.cfg` autoload 保证必加载 |
| ESC 关不掉菜单 | 同样走轮询（`KEY_ESCAPE`） |
| 开关点了没反应 | `connect` 的 binds 顺序兼容写法；先看日志有没有 `[toggle]` |
| 免费商店/免费刷新不生效 | 字段是**按玩家分的数组**，用 `_set_shop_field()` 统一处理 |
| 无敌无效 | `disable_hurtbox()` + 停 `_invincibility_timer` / `_lose_health_timer` |
| 跳过一波不结算 | 让 `RunData.wave_timer` 立刻超时（`instant_waves` 只对下一波生效） |
| 脚本改崩了 | 改完立刻跑「自定义函数调用完整性」静态检查 + 看 `godot.log` 有无 Parse Error |
| 存档/版本差异 | 运行时 `get_property_list()` / `get_method_list()` 打出来对照 |

---

## 12.7 如果你只记住三句话

1. **不确定就 dump**：把 `get_method_list()` / `get_property_list()` / `typeof()` 打出来，
   别猜。猜是这个项目最大的时间黑洞。
2. **改流程优于改状态**：让游戏走它自己的流程（触发计时器超时、调用它自己的方法），
   比伪造数值可靠得多。
3. **每一环都要有日志**：用户说「没生效」时，你要能立刻指出断在哪一环。
