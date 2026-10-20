extends Node

# Brotato 1.1.x 本地作弊 Mod
#   F2  : 打开 / 关闭作弊菜单（ESC 关闭；也可点左下角 “F2 作弊”）
#   F3  : 无限金币   F4 : 无敌   F5 : 清空本波敌人   F6 : 自动清怪
# 所有开关默认关闭，用到再开。

const MOD_ID := "Local-Cheat"
const THEME_PATH := "res://resources/themes/base_theme.tres"
const CJK_FONT_PATH := "res://resources/fonts/raw/NotoSansSC-Medium.otf"

# ---------------- 开关状态 ----------------
var infinite_gold := false
var auto_level := false
var free_shop := false
var free_reroll := false
var god_mode := false
var auto_heal := false
var huge_hp := false
var infinite_lifesteal := false
var no_cooldown := false
var auto_clear := false

var gold_target := 999999
var stat_value := 1000

# ---------------- 内部 ----------------
var _menu_open := false
var _tick := 0.0
var _instant_timer := 0.0
var _toast_time := 0.0
var _layout_logged := false
var _shop_logged := false
var _shop_dbg_t := 0.0
var _shop_cache = null
var _orig_hp := {}
var _orig_item_price := {}

var _ui: CanvasLayer
var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _hint: Label
var _toast: Label
var _status: Label
var _log_path := "user://Local-Cheat.log"
var _tg := {}


func _ready() -> void:
	# 同一脚本可能被加载两次（autoload + ModLoader），只让第一个建 UI
	var tree = get_tree()
	if tree != null:
		if tree.has_meta("local_cheat_built"):
			return
		tree.set_meta("local_cheat_built", true)
	_build_ui()
	_log("[%s] loaded | F2 菜单 | F3 金币 | F4 无敌 | F5 清怪 | F6 自动清怪 | ESC 关闭" % MOD_ID)
	_update_ui()


# ================================================================ 工具
func _log(msg: String) -> void:
	print(msg)
	var f := File.new()
	if f.open(_log_path, File.READ_WRITE) != OK:
		f.open(_log_path, File.WRITE)
		f.close()
		f.open(_log_path, File.READ_WRITE)
	if f.open(_log_path, File.READ_WRITE) == OK:
		f.seek_end()
		f.store_line(msg)
		f.close()


func _toast_show(msg: String) -> void:
	if _toast == null:
		return
	_toast.text = msg
	_toast.visible = true
	_toast_time = 2.0


func _props(obj) -> Array:
	var out := []
	if obj == null:
		return out
	var lst: Array = obj.get_property_list()
	for pr in lst:
		out.append(str(pr.get("name", "")))
	return out


func _method_names(obj) -> Array:
	var out := []
	if obj == null:
		return out
	var lst: Array = obj.get_method_list()
	for m in lst:
		var n = str(m.get("name", ""))
		if n != "" and not out.has(n):
			out.append(n)
	out.sort()
	return out


# ================================================================ UI
func _mk_font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	var data: Resource = load(CJK_FONT_PATH)
	if data != null:
		f.font_data = data
	f.size = size
	return f


func _mk_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = bw
	s.border_width_top = bw
	s.border_width_right = bw
	s.border_width_bottom = bw
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_right = 8
	s.corner_radius_bottom_left = 8
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _style_button(b: Button) -> void:
	var normal := _mk_style(Color(0.13, 0.14, 0.18, 0.96), Color(0.85, 0.85, 0.9, 0.45), 2)
	var hover := _mk_style(Color(0.26, 0.28, 0.34, 1.0), Color(1, 0.85, 0.4, 0.95), 2)
	b.add_stylebox_override("normal", normal)
	b.add_stylebox_override("hover", hover)
	b.add_stylebox_override("pressed", hover)
	b.add_stylebox_override("focus", normal)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 100
	add_child(_ui)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme_res: Resource = load(THEME_PATH)
	if theme_res is Theme:
		_root.theme = theme_res
	_ui.add_child(_root)

	var f_body := _mk_font(16)
	var f_title := _mk_font(22)
	var f_sec := _mk_font(14)
	var f_tiny := _mk_font(12)

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	_root.add_child(_dim)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pstyle := _mk_style(Color(0.07, 0.08, 0.10, 0.97), Color(0.95, 0.78, 0.32, 0.85), 3)
	pstyle.content_margin_left = 26
	pstyle.content_margin_right = 26
	pstyle.content_margin_top = 20
	pstyle.content_margin_bottom = 20
	_panel.add_stylebox_override("panel", pstyle)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_constant_override("separation", 12)
	_panel.add_child(col)

	var title := Label.new()
	title.text = "土豆兄弟 · 作弊菜单"
	title.add_font_override("font", f_title)
	title.horizontal_align = Label.ALIGN_CENTER
	col.add_child(title)

	_status = Label.new()
	_status.add_font_override("font", f_body)
	_status.horizontal_align = Label.ALIGN_CENTER
	col.add_child(_status)

	col.add_child(_section_label("开关", f_sec))
	col.add_child(_separator())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("h_separation", 28)
	grid.add_constant_override("v_separation", 6)
	col.add_child(grid)

	_add_toggle(grid, "gold", "无限金币", f_body)
	_add_toggle(grid, "level", "无限经验", f_body)
	_add_toggle(grid, "shop", "免费商店", f_body)
	_add_toggle(grid, "reroll", "免费刷新", f_body)
	_add_toggle(grid, "god", "无敌模式", f_body)
	_add_toggle(grid, "heal", "自动回满血", f_body)
	_add_toggle(grid, "hp", "生命上限 999999", f_body)
	_add_toggle(grid, "lifesteal", "无限吸血", f_body)
	_add_toggle(grid, "cooldown", "无限冷却", f_body)
	_add_toggle(grid, "clear", "自动清怪", f_body)

	col.add_child(_section_label("操作", f_sec))
	col.add_child(_separator())
	var bgrid := GridContainer.new()
	bgrid.columns = 2
	bgrid.add_constant_override("h_separation", 28)
	bgrid.add_constant_override("v_separation", 8)
	col.add_child(bgrid)

	var b1 := _make_button(bgrid, "清空本波敌人", f_body)
	b1.connect("pressed", self, "_clear_wave")
	var b2 := _make_button(bgrid, "立刻结束本波", f_body)
	b2.connect("pressed", self, "_end_wave")
	var b3 := _make_button(bgrid, "全部关闭", f_body)
	b3.connect("pressed", self, "_reset_all")
	var b4 := _make_button(bgrid, "关闭 (ESC)", f_body)
	b4.connect("pressed", self, "_close_menu")

	var keys := Label.new()
	keys.text = "F2 菜单   F3 金币   F4 无敌   F5 清怪   F6 自动清怪   ESC 关闭"
	keys.add_font_override("font", f_tiny)
	keys.horizontal_align = Label.ALIGN_CENTER
	col.add_child(keys)

	_toast = Label.new()
	_toast.add_font_override("font", f_body)
	_toast.modulate = Color(1, 0.92, 0.55, 0.95)
	_toast.horizontal_align = Label.ALIGN_CENTER
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)

	_hint = Label.new()
	_hint.text = "F2 作弊"
	_hint.add_font_override("font", f_tiny)
	_hint.modulate = Color(1, 1, 1, 0.55)
	_hint.mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.connect("gui_input", self, "_on_hint_input")
	_root.add_child(_hint)


func _section_label(text: String, font: DynamicFont) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.modulate = Color(0.95, 0.78, 0.32, 0.95)
	return l


func _separator() -> HSeparator:
	var s := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color(0.95, 0.78, 0.32, 0.35)
	line.thickness = 1
	s.add_stylebox_override("separator", line)
	return s


func _add_toggle(parent: Node, id: String, text: String, font: DynamicFont) -> void:
	var b := CheckButton.new()
	b.text = text
	b.add_font_override("font", font)
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(205, 28)
	var empty := StyleBoxEmpty.new()
	b.add_stylebox_override("normal", empty)
	b.add_stylebox_override("hover", empty)
	b.add_stylebox_override("pressed", empty)
	b.add_stylebox_override("focus", empty)
	b.add_stylebox_override("disabled", empty)
	parent.add_child(b)
	b.connect("toggled", self, "_on_toggle_changed", [id])
	_tg[id] = b


func _make_button(parent: Node, text: String, font: DynamicFont) -> Button:
	var b := Button.new()
	b.text = text
	b.add_font_override("font", font)
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(205, 34)
	_style_button(b)
	parent.add_child(b)
	return b


func _on_hint_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == BUTTON_LEFT:
			_menu_open = not _menu_open
			_update_ui()
			_toast_show("作弊菜单：已打开" if _menu_open else "作弊菜单：已关闭")


func _set_rect(c: Control, pos: Vector2, size: Vector2) -> void:
	if c == null:
		return
	c.rect_position = pos
	c.rect_size = size


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_set_rect(_root, Vector2.ZERO, vs)
	_set_rect(_dim, Vector2.ZERO, vs)
	if _panel != null:
		var ms := _panel.get_combined_minimum_size()
		if ms.x > 10.0 and ms.y > 10.0:
			if ms.y > vs.y - 40.0:
				ms.y = vs.y - 40.0
			_set_rect(_panel, Vector2(floor((vs.x - ms.x) * 0.5), floor((vs.y - ms.y) * 0.5)), ms)
	_set_rect(_hint, Vector2(10, vs.y - 30), Vector2(90, 22))
	if _toast != null:
		var tw := _toast.get_combined_minimum_size().x
		if tw < 10.0:
			tw = 300.0
		_set_rect(_toast, Vector2(floor((vs.x - tw) * 0.5), 70), Vector2(tw, 30))
	if _panel != null and _menu_open and not _layout_logged:
		_layout_logged = true
		_log("[layout] viewport=" + str(vs) + " panel_rect=" + str(_panel.get_rect()))


func _update_ui() -> void:
	if _panel == null:
		return
	_panel.visible = _menu_open
	_dim.visible = _menu_open
	_tg["gold"].set_pressed_no_signal(infinite_gold)
	_tg["level"].set_pressed_no_signal(auto_level)
	_tg["shop"].set_pressed_no_signal(free_shop)
	_tg["reroll"].set_pressed_no_signal(free_reroll)
	_tg["god"].set_pressed_no_signal(god_mode)
	_tg["heal"].set_pressed_no_signal(auto_heal)
	_tg["hp"].set_pressed_no_signal(huge_hp)
	_tg["lifesteal"].set_pressed_no_signal(infinite_lifesteal)
	_tg["cooldown"].set_pressed_no_signal(no_cooldown)
	_tg["clear"].set_pressed_no_signal(auto_clear)
	_status.text = "金币 %s    波次 %s    等级 %s    血量 %s" % [
		_gold_txt(), _rd_txt("current_wave"), _level_txt(), _hp_txt()]
	_layout()


# ================================================================ 输入
# 用「轮询按键状态」而不是 _input 事件：
# 游戏自己的节点可能先消费掉按键事件，轮询则完全不受事件传播顺序影响。
const KEY_MAP := [
	[KEY_F2, "menu"],
	[KEY_F3, "gold"],
	[KEY_F4, "god"],
	[KEY_F5, "clearwave"],
	[KEY_F6, "autoclear"],
	[KEY_ESCAPE, "esc"],
]

var _key_down := {}


func _poll_keys() -> void:
	for entry in KEY_MAP:
		var code = entry[0]
		var id = str(entry[1])
		var down = Input.is_key_pressed(code)
		var was = bool(_key_down.get(id, false))
		_key_down[id] = down
		if down and not was:
			_handle_key_id(id)


func _handle_key_id(id: String) -> void:
	match id:
		"menu":
			_menu_open = not _menu_open
			_update_ui()
			_toast_show("作弊菜单：已打开" if _menu_open else "作弊菜单：已关闭")
			_log("[key] F2 菜单 -> " + str(_menu_open))
		"gold":
			_set_toggle("gold", not _tg["gold"].pressed)
		"god":
			_set_toggle("god", not _tg["god"].pressed)
		"clearwave":
			_clear_wave()
		"autoclear":
			_set_toggle("clear", not _tg["clear"].pressed)
		"esc":
			if _menu_open:
				_close_menu()
				_toast_show("作弊菜单：已关闭")
				_log("[key] ESC 关闭菜单")


# ================================================================ 开关
func _on_toggle_changed(a = null, b = null) -> void:
	var id := ""
	var pressed := false
	if typeof(a) == TYPE_STRING:
		id = str(a)
		pressed = bool(b)
	else:
		pressed = bool(a)
		id = str(b)
	if id == "":
		return
	_log("[toggle] id=" + id + " pressed=" + str(pressed))
	_set_toggle(id, pressed)


func _set_toggle(id: String, value: bool) -> void:
	match id:
		"gold": _on_gold(value)
		"level": _on_level(value)
		"shop": _on_shop(value)
		"reroll": _on_reroll(value)
		"god": _on_god(value)
		"heal": _on_heal(value)
		"hp": _on_hp(value)
		"lifesteal": _on_lifesteal(value)
		"cooldown": _on_cooldown(value)
		"clear": _on_clear(value)
	_update_ui()


func _on_gold(v: bool) -> void:
	infinite_gold = v
	_log("[%s] 无限金币 -> %s" % [MOD_ID, str(v)])
	_toast_show("无限金币：开" if v else "无限金币：关")


func _on_level(v: bool) -> void:
	auto_level = v
	_toast_show("无限经验：开" if v else "无限经验：关")


func _on_shop(v: bool) -> void:
	free_shop = v
	_apply_shop_cheats()
	_toast_show("免费商店：开" if v else "免费商店：关")


func _on_reroll(v: bool) -> void:
	free_reroll = v
	_apply_shop_cheats()
	_toast_show("免费刷新：开" if v else "免费刷新：关")


func _on_god(v: bool) -> void:
	god_mode = v
	var rd = get_node_or_null("/root/RunData")
	if rd != null:
		rd.set("invulnerable", v)
	_log("[%s] 无敌 -> %s" % [MOD_ID, str(v)])
	_toast_show("无敌模式：开" if v else "无敌模式：关")


func _on_heal(v: bool) -> void:
	auto_heal = v
	_toast_show("自动回满血：开" if v else "自动回满血：关")


func _on_hp(v: bool) -> void:
	huge_hp = v
	_apply_huge_hp()
	_toast_show("生命上限999999：开" if v else "生命上限999999：关")


func _on_lifesteal(v: bool) -> void:
	infinite_lifesteal = v
	_apply_stat("stat_lifesteal", stat_value if v else -stat_value)
	_toast_show("无限吸血：开" if v else "无限吸血：关")


func _on_cooldown(v: bool) -> void:
	no_cooldown = v
	_apply_stat("stat_attack_speed", stat_value if v else -stat_value)
	_toast_show("无限冷却：开" if v else "无限冷却：关")


func _on_clear(v: bool) -> void:
	auto_clear = v
	_toast_show("自动清怪：开" if v else "自动清怪：关")


func _reset_all() -> void:
	infinite_gold = false
	auto_level = false
	free_shop = false
	free_reroll = false
	god_mode = false
	auto_heal = false
	huge_hp = false
	infinite_lifesteal = false
	no_cooldown = false
	auto_clear = false
	_apply_stat("stat_lifesteal", -stat_value)
	_apply_stat("stat_attack_speed", -stat_value)
	_apply_huge_hp()
	_apply_shop_cheats()
	var rd = get_node_or_null("/root/RunData")
	if rd != null:
		rd.set("invulnerable", false)
		rd.set("instant_waves", false)
	_update_ui()
	_toast_show("已全部关闭")
	_log("[%s] reset all" % MOD_ID)


func _close_menu() -> void:
	_menu_open = false
	_update_ui()


# ================================================================ 功能实现
func _clear_wave(quiet: bool = false) -> void:
	var killed := 0
	for e in _find_enemies():
		if not is_instance_valid(e):
			continue
		if bool(e.get("dead")):
			continue
		if e.has_method("take_damage"):
			e.call("take_damage", 999999, null, false, false)
		if is_instance_valid(e) and not bool(e.get("dead")) and e.has_method("die"):
			e.call("die")
		killed += 1
	if not quiet:
		_log("[%s] 清怪 %d 只" % [MOD_ID, killed])
		_toast_show("已清怪 %d 只" % killed)
		_update_ui()


func _end_wave() -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd == null:
		return
	var t = rd.get("wave_timer")
	if t != null:
		t.set("wait_time", 0.15)
		t.call("start")
		_toast_show("本波即将结算…")
	else:
		rd.set("instant_waves", true)
		_instant_timer = 1.5
		_toast_show("本波即将结算…")
	_clear_wave(true)
	_update_ui()


func _apply_god_mode() -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd != null:
		rd.set("invulnerable", true)
	for p in _get_players():
		if p.has_method("disable_hurtbox"):
			p.call("disable_hurtbox")
		var inv_t = p.get("_invincibility_timer")
		if inv_t != null and inv_t is Timer:
			inv_t.stop()
		var lose_t = p.get("_lose_health_timer")
		if lose_t != null and lose_t is Timer:
			lose_t.stop()
		var st: Object = p.get("current_stats")
		var ms: Object = p.get("max_stats")
		if st == null or ms == null:
			continue
		if huge_hp and "health" in ms:
			ms.set("health", 999999)
		if auto_heal and "health" in st and "health" in ms:
			st.set("health", ms.get("health"))


func _apply_huge_hp() -> void:
	var pls := _get_players()
	for i in range(pls.size()):
		var ms: Object = pls[i].get("max_stats")
		if ms == null or not ("health" in ms):
			continue
		if huge_hp:
			if not _orig_hp.has(i):
				_orig_hp[i] = ms.get("health")
			ms.set("health", 999999)
		elif _orig_hp.has(i):
			ms.set("health", _orig_hp[i])
			_orig_hp.erase(i)


# ---------------- 商店 ----------------
# 1.1.x 的商店价格/免费次数是「按玩家分的数组」：
#   _reroll_price = [59, 0, 0, 0]   ← 每个玩家一个刷新价
#   _free_rerolls = [0, 0, 0, 0]    ← 每个玩家的免费刷新次数
# 所以要逐个玩家写，不能当标量赋值。
#
# 刷新：把免费次数拉满 + 把刷新价清零 + 打开 bonus 免费标记
# 商品：ShopItem.value 是实际扣费金额，清零即免费，并刷新按钮上的显示
func _apply_shop_cheats() -> void:
	var shops := []
	if _shop_cache != null and is_instance_valid(_shop_cache):
		shops = [_shop_cache]
	else:
		shops = _find_shops()
		if shops.size() > 0:
			_shop_cache = shops[0]
	if shops.size() == 0:
		if not _shop_logged:
			_shop_logged = true
			_log("[shop] 没找到商店节点（当前不在商店界面？）")
		return
	for shop in shops:
		if not _shop_logged:
			_shop_logged = true
			_log("[shop] node=" + str(shop.get_path()) + " visible=" + str(shop.is_visible_in_tree())
				+ " reroll_price=" + str(shop.get("_reroll_price"))
				+ " free_rerolls=" + str(shop.get("_free_rerolls")))
			var ms: Array = []
			for m in _method_names(shop):
				if m.find("reroll") != -1 or m.find("price") != -1:
					ms.append(m)
			_log("[shop] reroll/price methods: " + str(ms))
			var its = shop.get("_shop_items")
			if typeof(its) == TYPE_ARRAY and its.size() > 0:
				var it0 = its[0]
				if typeof(it0) == TYPE_OBJECT:
					_log("[shop] item0 value=" + str(it0.get("value")) + " type=" + str(typeof(it0.get("value"))))
		if free_reroll:
			var before_price = str(shop.get("_reroll_price"))
			var before_free = str(shop.get("_free_rerolls"))
			_set_shop_field(shop, "_free_rerolls", 999)
			_set_shop_field(shop, "_reroll_price", 0)
			shop.set("_has_bonus_free_reroll", true)
			if shop.has_method("set_reroll_button_price"):
				shop.call("set_reroll_button_price")
			_set_reroll_button_label(shop, 0)
			_shop_dbg_t += 0.2
			if _shop_dbg_t >= 0.6:
				_shop_dbg_t = 0.0
				_log("[shop] price " + before_price + " -> " + str(shop.get("_reroll_price"))
					+ " | free " + before_free + " -> " + str(shop.get("_free_rerolls"))
					+ " | gold=" + str(_gold_txt())
					+ " | btn=" + str(_reroll_button_text(shop)))
		var items = shop.get("_shop_items")
		if typeof(items) != TYPE_ARRAY:
			continue
		for it in items:
			if typeof(it) != TYPE_OBJECT:
				continue
			if not ("value" in it):
				continue
			var key = it.get_instance_id()
			if free_shop:
				if not _orig_item_price.has(key):
					_orig_item_price[key] = it.get("value")
				_set_shop_field(it, "value", 0)
				_set_shop_item_label(it, 0)
			elif _orig_item_price.has(key):
				_set_shop_field(it, "value", _orig_item_price[key])
				_set_shop_item_label(it, _orig_item_price[key])
				_orig_item_price.erase(key)


# 数组就逐个元素写，标量就直接赋值
func _set_shop_field(obj, field: String, value) -> void:
	var cur = obj.get(field)
	if typeof(cur) == TYPE_ARRAY:
		for i in range(cur.size()):
			cur[i] = value
	else:
		obj.set(field, value)


func _set_shop_item_label(item, value) -> void:
	var btn = item.get("_button")
	if btn != null and typeof(btn) == TYPE_OBJECT and btn.has_method("set_value"):
		btn.call("set_value", value)


func _reroll_button_text(shop) -> String:
	var btn = _find_node_named(shop, "RerollButton")
	if btn == null:
		return "no-button"
	var txt := ""
	for c in btn.get_children():
		if c is Label:
			txt = c.text
			break
	if txt == "" and ("value" in btn):
		txt = str(btn.get("value"))
	return txt


# 刷新按钮上的价格显示（按钮节点名可能变，找不到就跳过）
func _set_reroll_button_label(shop, value) -> void:
	var btn = _find_node_named(shop, "RerollButton")
	if btn == null:
		return
	if btn.has_method("set_value"):
		btn.call("set_value", value)
	elif "value" in btn:
		btn.set("value", value)


# ---------------- 属性 ----------------
func _apply_stat(key: String, value: int) -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd == null:
		return
	var argc := 2
	var lst: Array = rd.get_method_list()
	for m in lst:
		if str(m.get("name", "")) == "add_stat":
			argc = (m.get("args") as Array).size()
			break
	var n: int = _player_count()
	if n <= 0:
		return
	for i in range(n):
		if argc >= 3:
			rd.call("add_stat", key, value, i)
		else:
			rd.call("add_stat", key, value)
	_log("[%s] stat %s %s" % [MOD_ID, key, str(value)])


# ================================================================ 主循环
func _process(delta: float) -> void:
	_poll_keys()
	_layout()
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and _toast != null:
			_toast.visible = false
	if _instant_timer > 0.0:
		_instant_timer -= delta
		if _instant_timer <= 0.0:
			var rd0 = get_node_or_null("/root/RunData")
			if rd0 != null:
				rd0.set("instant_waves", false)
	if god_mode or huge_hp or auto_heal:
		_apply_god_mode()
	if free_shop or free_reroll:
		_apply_shop_cheats()
	_tick += delta
	if _tick < 0.2:
		return
	_tick = 0.0
	if _menu_open:
		_update_ui()
	if infinite_gold:
		_apply_gold()
	if auto_level:
		_apply_xp()
	if auto_clear:
		_clear_wave(true)


func _apply_gold() -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_gold") or not rd.has_method("add_gold"):
		return
	var n: int = _player_count()
	if n <= 0:
		return
	for i in range(n):
		var gold: int = rd.get_player_gold(i)
		if gold < gold_target:
			rd.add_gold(gold_target - gold, i)


func _apply_xp() -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("add_xp"):
		return
	var n: int = _player_count()
	if n <= 0:
		return
	for i in range(n):
		rd.call("add_xp", 50, i)


# ================================================================ 数据读取
func _player_count() -> int:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_count"):
		return 0
	var pc = rd.get_player_count()
	if typeof(pc) == TYPE_INT:
		return pc
	return pc.size()


func _rd_txt(prop: String) -> String:
	var rd = get_node_or_null("/root/RunData")
	if rd == null:
		return "-"
	var v = rd.get(prop)
	if v == null:
		return "-"
	return str(v)


func _gold_txt() -> String:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_gold"):
		return "-"
	var n: int = _player_count()
	if n <= 0:
		return "-"
	return str(rd.get_player_gold(0))


func _level_txt() -> String:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_level"):
		return "-"
	var n: int = _player_count()
	if n <= 0:
		return "-"
	return str(rd.get_player_level(0))


func _hp_txt() -> String:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_current_health"):
		return "-"
	var n: int = _player_count()
	if n <= 0:
		return "-"
	return str(rd.get_player_current_health(0)) + "/" + str(rd.get_player_max_health(0))


# ================================================================ 节点查找
# 找到所有真正的商店节点（排除 shop_item.gd / base_shop.gd）
func _find_shops() -> Array:
	var out := []
	var root := get_tree().get_root()
	if root == null:
		return out
	var stack: Array = [root]
	while not stack.empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc: Object = n.get_script()
		if sc == null:
			continue
		var path := str(sc.resource_path)
		if path.find("/ui/menus/shop/") == -1:
			continue
		if path.find("shop_item.gd") != -1 or path.find("base_shop.gd") != -1:
			continue
		if not ("_shop_items" in n):
			continue
		out.append(n)
	return out


func _find_enemies() -> Array:
	var out := []
	var root := get_tree().get_root()
	if root == null:
		return out
	var entities = _find_node_named(root, "Entities")
	var list: Array = []
	if entities != null:
		for c in entities.get_children():
			list.append(c)
	if list.empty():
		list = root.find_children("*", "", true, false)
	for e in list:
		if not is_instance_valid(e):
			continue
		var sc: Object = e.get_script()
		if sc == null:
			continue
		var path := str(sc.resource_path)
		if path.find("/enemies/") != -1 or path.find("enemy.gd") != -1:
			out.append(e)
	return out


func _find_node_named(from: Node, node_name: String) -> Node:
	var stack: Array = [from]
	while not stack.empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.name == node_name:
			return n
	return null


func _get_players() -> Array:
	var out := []
	var root := get_tree().get_root()
	if root == null:
		return out
	var entities = _find_node_named(root, "Entities")
	if entities != null:
		for c in entities.get_children():
			if _is_player_node(c):
				out.append(c)
	if out.empty():
		var list: Array = root.find_children("*", "", true, false)
		for n in list:
			if _is_player_node(n):
				out.append(n)
	return out


func _is_player_node(n) -> bool:
	if not is_instance_valid(n):
		return false
	var sc: Object = n.get_script()
	if sc == null:
		return false
	var path := str(sc.resource_path)
	return path.find("/units/player/") != -1
