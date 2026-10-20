extends Node

# Brotato 1.1.x 本地作弊 Mod
# 菜单：F2 打开 / ESC 关闭（也可点左下角 "F2 作弊"）
# 快捷键：F3 无限金币 · F4 无敌 · F5 清空本波敌人 · F6 自动清怪
# 所有开关默认关闭，用到再开。

const MOD_ID := "Local-Cheat"
const THEME_PATH := "res://resources/themes/base_theme.tres"
const CJK_FONT_PATH := "res://resources/fonts/raw/NotoSansSC-Medium.otf"

# ---- 开关状态 ----
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

# ---- UI ----
var _menu_open := false
var _tick := 0.0
var _instant_timer := 0.0
var _toast_time := 0.0
var _layout_logged := false
var _effect_logged := false
var _orig_hp := {}

var _ui: CanvasLayer
var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _hint: Label
var _toast: Label
var _status: Label
var _log_path := "user://Local-Cheat.log"

var _tg: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_log("[%s] loaded | F2 菜单 | F3 金币 | F4 无敌 | F5 清怪 | F6 自动清怪 | ESC 关闭" % MOD_ID)
	_update_ui()


# ================================================================ 日志
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


# ================================================================ UI 构建
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

	# ---- 开关区（两列） ----
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

	# ---- 操作区（两列） ----
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
	# 去掉主题自带的黑色方框，只显示开关本体
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


# ================================================================ 布局
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
	if _panel != null and not _layout_logged:
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
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	if _menu_open and (_is_key(k, KEY_ESCAPE) or event.is_action_pressed("ui_cancel")):
		_close_menu()
		get_viewport().set_input_as_handled()
		return
	if _is_key(k, KEY_F2):
		_menu_open = not _menu_open
		_update_ui()
		_toast_show("作弊菜单：已打开" if _menu_open else "作弊菜单：已关闭")
	elif _is_key(k, KEY_F3):
		_set_toggle("gold", not _tg["gold"].pressed)
	elif _is_key(k, KEY_F4):
		_set_toggle("god", not _tg["god"].pressed)
	elif _is_key(k, KEY_F5):
		_clear_wave()
	elif _is_key(k, KEY_F6):
		_set_toggle("clear", not _tg["clear"].pressed)
	else:
		return
	get_viewport().set_input_as_handled()


func _is_key(k: InputEventKey, key: int) -> bool:
	if k.scancode == key or k.physical_scancode == key:
		return true
	var low := key & 0xFFFFFF
	if (k.scancode & 0xFFFFFF) != low:
		return false
	return (k.scancode >> 24) == 1 or (k.scancode >> 22) == 1


# ================================================================ 开关
func _on_toggle_changed(id: String, pressed: bool) -> void:
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
	_apply_free_shop()
	_toast_show("免费商店：开" if v else "免费商店：关")


func _on_reroll(v: bool) -> void:
	free_reroll = v
	_apply_free_reroll()
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
	_apply_free_shop()
	_apply_free_reroll()
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
# 清空本波敌人
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


# 立刻结束本波：让本波计时器马上超时
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


# 无敌 / 回血 / 生命上限
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


# 生命上限：记住原值以便还原
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


# 免费商店：把 items_price / reroll_price 的价格加成压到 0
func _apply_free_shop() -> void:
	if free_shop:
		_apply_stat("items_price", -100)
		_set_effect("items_price", 0)
	else:
		_apply_stat("items_price", 100)
		_set_effect("items_price", 100)


# 免费刷新：free_rerolls 拉满 + reroll_price 压到 0
func _apply_free_reroll() -> void:
	if free_reroll:
		_apply_stat("reroll_price", -100)
		_set_effect("free_rerolls", 999)
	else:
		_apply_stat("reroll_price", 100)
		_set_effect("free_rerolls", 0)


# 通用：写玩家效果（自动兼容字符串键 / 哈希键）
func _set_effect(key: String, value) -> void:
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_effects"):
		return
	var n: int = _player_count()
	if n <= 0:
		return
	var used_hash := false
	for i in range(n):
		var effs = rd.get_player_effects(i)
		if effs == null:
			continue
		if effs.has(key):
			effs[key] = value
		else:
			var keys = get_node_or_null("/root/Keys")
			if keys == null:
				continue
			effs[keys.call("generate_hash", key)] = value
			used_hash = true
	if not _effect_logged:
		_effect_logged = true
		_log("[effect] sample keys: " + str(_effect_keys()) + " hashed=" + str(used_hash))


func _effect_keys() -> Array:
	var out := []
	var rd = get_node_or_null("/root/RunData")
	if rd == null or not rd.has_method("get_player_effects"):
		return out
	var n: int = _player_count()
	if n <= 0:
		return out
	var effs = rd.get_player_effects(0)
	if effs == null:
		return out
	var keys: Array = effs.keys()
	for i in range(min(30, keys.size())):
		out.append(str(keys[i]))
	return out


# 通用：加减属性（兼容不同参数个数）
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
	if free_shop or free_reroll:
		_apply_free_shop()
		_apply_free_reroll()
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
