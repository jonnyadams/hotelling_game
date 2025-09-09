extends Node2D

const ICON_BLUE:   Texture2D = preload("res://assets/beach_person_blue.png")
const ICON_RED:    Texture2D = preload("res://assets/beach_person_red.png")
const ICON_FLOATY: Texture2D = preload("res://assets/beach_person_floaty.png")
const ICON_MALE:   Texture2D = preload("res://assets/beach_male_hat_64_new.png")
const ICON_FEMALE: Texture2D = preload("res://assets/beach_female_bikini_64_new.png")
const PRESET_WIDE_ACTION      := "preset_vendors_wide"      # key 1 → [0.05, 0.95]
const PRESET_CENTERED_ACTION  := "preset_vendors_centered"  # key 2 → [0.49, 0.51]

var _preset1_armed: bool = false
var _preset2_armed: bool = false


@onready var beach: Node2D            = $Beach
@onready var vendor_a: Node2D         = $Vendors/VendorA
@onready var vendor_b: Node2D         = $Vendors/VendorB
@onready var consumers_root: Node2D   = $Consumers
@onready var ui_root: Control         = $UI/Control if has_node("UI/Control") else null

@export var ui_font_size: int = 30 : set = set_ui_font_size

# --- PRICES & TRANSPORT COST (sliders control these) ---
@export var price_a: float = 2.50
@export var price_b: float = 2.50
@export var transport_cost: float = 5.00   # "t" in Hotelling

# --- CAMERA SETTINGS ---
@onready var cam: Camera2D = $Camera2D

@export var zoom_step: float = 0.1       # wheel increment
@export var zoom_max: float = 3.0        # max zoom IN (bigger)
var zoom_level: float = 1.0              # current zoom
var _panning: bool = false
var _last_mouse: Vector2

@export var ui_visible: bool = true : set = set_ui_visible
const UI_TOGGLE_ACTION := "toggle_ui"


@export var start_paused: bool = true 
const PAUSE_ACTION := "toggle_pause"

# --- SPAWNING ---
@export var consumers_initial: int = 10
@export var spawn_interval: float = 0.5
@export var consumers_y_offset: float = -30.0
@export var consumers_y_jitter: float = 150.0
var _spawn_timer: Timer

# --- SALES / REVENUE ---
var sales_a: int = 0
var sales_b: int = 0
var revenue_a: float = 0.0
var revenue_b: float = 0.0

# Optional: if you used the pixel people textures, you may have preloads here

func _ready() -> void:
	if ui_root: 
		ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
		ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		ui_root.offset_left = 0
		ui_root.offset_top = 0
		ui_root.offset_right = 0
		ui_root.offset_bottom = 0

	_ensure_pause_input()
	if start_paused:
		get_tree().paused = true

	# UI should still be usable while paused
	if ui_root:
		ui_root.process_mode = Node.PROCESS_MODE_ALWAYS

	if start_paused:
		get_tree().paused = true


	if start_paused:
		get_tree().paused = true
	_ensure_pricing_ui()
	_ensure_center_price_box()
	
	_apply_global_ui_font_size()
	_update_from_vendor_positions()

	# initial burst
	for i in range(consumers_initial):
		_spawn_one_consumer()

	# continuous spawns
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = max(0.05, spawn_interval)
	_spawn_timer.one_shot = false
	add_child(_spawn_timer)
	_spawn_timer.timeout.connect(_spawn_one_consumer)
	_spawn_timer.start()

	_update_sales_labels()
	
	_mark_simulation_pausable()
	
	_apply_zoom()             # set initial zoom & clamp
	_clamp_camera_to_world()  # center correctly
	
	_ensure_input_actions()
	set_ui_visible(ui_visible) 

# =======================================================
#   HOTELLING: split and delivered price choice
# =======================================================
func _update_from_vendor_positions() -> void:
	var xa: float = (vendor_a as Object).get("x_norm") as float
	var xb: float = (vendor_b as Object).get("x_norm") as float

	# Handle t == 0: if same price, no split; else all go to cheaper
	if transport_cost <= 0.0:
		if is_equal_approx(price_a, price_b):
			(beach as Object).call("clear_split")
		else:
			var split_norm: float = 1.0 if price_a < price_b else 0.0
			(beach as Object).call("set_split_x_from_norm", split_norm)
		return

	# General split formula: x* = (pB - pA + t(a+b)) / (2t)
	var split_norm: float = (price_b - price_a + transport_cost * (xa + xb)) / (2.0 * transport_cost)
	split_norm = clampf(split_norm, 0.0, 1.0)
	(beach as Object).call("set_split_x_from_norm", split_norm)

# Best vendor by delivered price for a given normalized position x in [0,1]
# Returns true if A is chosen, false if B
func _best_vendor_for_x_norm(xn: float) -> bool:
	var xa: float = (vendor_a as Object).get("x_norm") as float
	var xb: float = (vendor_b as Object).get("x_norm") as float
	var cost_a: float = price_a + transport_cost * absf(xn - xa)
	var cost_b: float = price_b + transport_cost * absf(xn - xb)
	if is_equal_approx(cost_a, cost_b):
		# tie-breaker: nearer by distance
		return absf(xn - xa) <= absf(xn - xb)
	return cost_a < cost_b

# Convert a consumer's current x (pixels) to the target stall x (pixels) under delivered-price rule
func _target_px_for_x(x_px: float) -> float:
	var xn: float = (beach as Object).call("px_to_norm", x_px) as float
	var xa: float = (vendor_a as Object).get("x_norm") as float
	var xb: float = (vendor_b as Object).get("x_norm") as float
	var va_px: Vector2 = (beach as Object).call("norm_to_px", xa) as Vector2
	var vb_px: Vector2 = (beach as Object).call("norm_to_px", xb) as Vector2
	return va_px.x if _best_vendor_for_x_norm(xn) else vb_px.x

# =======================================================
#   SPAWNING & ARRIVALS
# =======================================================
func _spawn_one_consumer() -> void:
	var rng := RandomNumberGenerator.new(); rng.randomize()
	var x_norm: float = rng.randf()
	var start_px: Vector2 = (beach as Object).call("norm_to_px", x_norm) as Vector2
	var beach_y: float = (beach as Object).get("beach_y") as float
	var r := rng.randf()

	start_px.y = beach_y + consumers_y_offset + rng.randf_range(-consumers_y_jitter, consumers_y_jitter)

	var c: Consumer = Consumer.new()
	consumers_root.add_child(c)
	c.process_mode = Node.PROCESS_MODE_PAUSABLE
	c.icon = ICON_BLUE if rng.randf() < 0.5 else ICON_RED
	c.pixel_scale = 2  # 2=32x32 on screen (since the PNGs are 16x16

	c.target_x = _target_px_for_x(start_px.x)
	c.setup(start_px, c.target_x, rng.randf())
	c.arrived.connect(_on_consumer_arrived)

func _retarget_consumers() -> void:
	for n in consumers_root.get_children():
		if n is Consumer:
			var c := n as Consumer
			c.target_x = _target_px_for_x(c.position.x)
			c.done = false

func _on_consumer_arrived(world_pos: Vector2) -> void:
	# Attribute by delivered price at arrival position
	var xn: float = (beach as Object).call("px_to_norm", world_pos.x) as float
	var chosen_a: bool = _best_vendor_for_x_norm(xn)

	if chosen_a:
		sales_a += 1
		revenue_a += price_a
	else:
		sales_b += 1
		revenue_b += price_b

	_update_sales_labels()

	# Spawn $ popup at the chosen stall in the vendor's color
	var hit_x: float
	var hit_color: Color
	var beach_y: float = (beach as Object).get("beach_y") as float
	if chosen_a:
		hit_x = ((beach as Object).call("norm_to_px", (vendor_a as Object).get("x_norm")) as Vector2).x
		hit_color = (vendor_a as Object).get("color") as Color
	else:
		hit_x = ((beach as Object).call("norm_to_px", (vendor_b as Object).get("x_norm")) as Vector2).x
		hit_color = (vendor_b as Object).get("color") as Color

	var fx := FloatingDollar.new()
	fx.process_mode = Node.PROCESS_MODE_PAUSABLE
	fx.color = hit_color
	fx.global_position = Vector2(hit_x, beach_y - 18.0)
	add_child(fx)

# =======================================================
#   UI: Sales/Revenue labels (uses your SalesBox)
# =======================================================
func _update_sales_labels() -> void:
	var total_sales: int = sales_a + sales_b
	var total_revenue: float = revenue_a + revenue_b

	var share_a_sales: float = float(sales_a) / float(max(1, total_sales))
	var share_b_sales: float = 1.0 - share_a_sales

	var share_a_rev: float = revenue_a / max(0.0001, total_revenue)
	var share_b_rev: float = 1.0 - share_a_rev

	if ui_root == null:
		return

	if ui_root.has_node("SalesBox/SalesALabel"):
		var la: Label = ui_root.get_node("SalesBox/SalesALabel") as Label
		la.text = "A revenue: $%.2f (%.0f%%) | sales: %d (%.0f%%)" % [
			revenue_a, round(share_a_rev * 100.0), sales_a, round(share_a_sales * 100.0)
		]
		la.modulate = (vendor_a as Object).get("color") as Color

	if ui_root.has_node("SalesBox/SalesBLabel"):
		var lb: Label = ui_root.get_node("SalesBox/SalesBLabel") as Label
		lb.text = "B revenue: $%.2f (%.0f%%) | sales: %d (%.0f%%)" % [
			revenue_b, round(share_b_rev * 100.0), sales_b, round(share_b_sales * 100.0)
		]
		lb.modulate = (vendor_b as Object).get("color") as Color

	if ui_root.has_node("SalesBox/TotalLabel"):
		var lt: Label = ui_root.get_node("SalesBox/TotalLabel") as Label
		lt.text = "Total revenue: $%.2f  |  Total sales: %d" % [total_revenue, total_sales]
		lt.modulate = Color(0.20, 0.20, 0.20)
# =======================================================
#   UI: create sliders if missing & wire them up
# =======================================================

func _dock_top_right(ctrl: Control, top_margin: float = 0.0, right_margin: float = 16.0) -> void:
	# Anchor to top-right
	ctrl.anchor_left = 1.0
	ctrl.anchor_right = 1.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_bottom = 0.0

	# Let containers compute their minimums
	ctrl.propagate_call("update_minimum_size")
	await get_tree().process_frame
	await get_tree().process_frame   # one extra frame helps after dynamic content

	var sz := ctrl.get_combined_minimum_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = ctrl.size  # fallback

	# Fix the rect to exactly the needed size at top-right
	ctrl.offset_right  = -right_margin
	ctrl.offset_left   = -right_margin - sz.x
	ctrl.offset_top    = top_margin
	ctrl.offset_bottom = top_margin + sz.y


func _ensure_pricing_ui() -> void:
	if ui_root == null: return
	var box: VBoxContainer
	if ui_root.has_node("PricingBox"):
		box = ui_root.get_node("PricingBox") as VBoxContainer
	else:
		box = VBoxContainer.new()
		box.name = "PricingBox"
		ui_root.add_child(box)
		box.add_theme_constant_override("separation", 8)
		box.mouse_filter = Control.MOUSE_FILTER_STOP

		_add_slider_row(box, "Price A", 0.00, 5.00, 0.50, price_a, _on_price_a_changed)
		_add_slider_row(box, "Price B", 0.00, 5.00, 0.50, price_b, _on_price_b_changed)
		_add_slider_row(box, "Transport Cost", 0.50, 30.00, 0.50, transport_cost, _on_t_changed)

	await _dock_top_right(box, 16.0, 16.0)  # <- dock *after* rows exist

func _ensure_center_price_box() -> void:
	if ui_root == null: return
	if ui_root.has_node("CenterBox"): return

	# A bar positioned near the top, centered horizontally
	var center := CenterContainer.new()
	center.name = "CenterBox"
	ui_root.add_child(center)

	# Anchor full width, fixed small height, offset a bit from the top
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.0
	center.anchor_bottom = 0.0
	center.offset_left = 0.0
	center.offset_right = 0.0
	center.offset_top = 12.0      # move up/down as you like
	center.offset_bottom = 44.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.name = "CenterRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	var la := Label.new(); la.name = "PriceALive"; row.add_child(la)
	var lb := Label.new(); lb.name = "PriceBLive"; row.add_child(lb)
	var lt := Label.new(); lt.name = "TransportLive"; row.add_child(lt)

	_refresh_center_box()


func _add_slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step: float, value: float, cb: Callable) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.mouse_filter = Control.MOUSE_FILTER_STOP         # <-- STOP
	
	var dark := Color(0.20, 0.20, 0.20)  # <- dark grey

	var lab := Label.new()
	lab.text = label_text + ":"
	lab.name = label_text.replace(" ", "") + "Label"
	lab.add_theme_color_override("font_color", dark)
	h.add_child(lab)

	var val := Label.new()
	val.name = label_text.replace(" ", "") + "Value"
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(val)

	var s := HSlider.new()
	s.name = label_text.replace(" ", "") + "Slider"
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_STOP         # <-- STOP (important)
	s.value_changed.connect(cb)
	parent.add_child(s)



func _refresh_pricing_labels() -> void:
	if ui_root == null:
		return
	if ui_root.has_node("PricingBox/PriceAValue"):
		(ui_root.get_node("PricingBox/PriceAValue") as Label).text = "$%.2f" % price_a
	if ui_root.has_node("PricingBox/PriceBValue"):
		(ui_root.get_node("PricingBox/PriceBValue") as Label).text = "$%.2f" % price_b
	if ui_root.has_node("PricingBox/TransporttValue"):
		(ui_root.get_node("PricingBox/TransporttValue") as Label).text = "%.2f" % transport_cost

# Slider callbacks
func _on_price_a_changed(v: float) -> void:
	price_a = v
	reset_sales_ui()
	_refresh_pricing_labels()
	_refresh_center_box()
	_update_from_vendor_positions()
	_retarget_consumers()

func _on_price_b_changed(v: float) -> void:
	price_b = v
	reset_sales_ui()
	_refresh_pricing_labels()
	_refresh_center_box()
	_update_from_vendor_positions()
	_retarget_consumers()

func _on_t_changed(v: float) -> void:
	transport_cost = v
	reset_sales_ui()
	_refresh_pricing_labels()
	_refresh_center_box()
	_update_from_vendor_positions()
	_retarget_consumers()

func _refresh_center_box() -> void:
	if ui_root == null: return
	if ui_root.has_node("CenterBox/CenterRow/PriceALive"):
		var la := ui_root.get_node("CenterBox/CenterRow/PriceALive") as Label
		la.text = "A: $%.2f" % price_a
		la.modulate = (vendor_a as Object).get("color") as Color
	if ui_root.has_node("CenterBox/CenterRow/PriceBLive"):
		var lb := ui_root.get_node("CenterBox/CenterRow/PriceBLive") as Label
		lb.text = "B: $%.2f" % price_b
		lb.modulate = (vendor_b as Object).get("color") as Color
	if ui_root.has_node("CenterBox/CenterRow/TransportLive"):
		var lt := ui_root.get_node("CenterBox/CenterRow/TransportLive") as Label
		lt.text = "Transport Cost: %.2f" % transport_cost
		lt.modulate = Color(0.2, 0.2, 0.2)  # neutral grey


# =======================================================
#   Reset (you already call this from Vendor drag start)
# =======================================================
func reset_sales_ui() -> void:
	sales_a = 0
	sales_b = 0
	revenue_a = 0.0
	revenue_b = 0.0
	_update_sales_labels()
	# (optional) clear $ popups
	for child in get_children():
		if child is FloatingDollar:
			child.queue_free()

func _ensure_pause_input() -> void:
	if not InputMap.has_action(PAUSE_ACTION):
		InputMap.add_action(PAUSE_ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SPACE
		InputMap.action_add_event(PAUSE_ACTION, ev)
		

func _toggle_pause() -> void:
	var st := get_tree()
	st.paused = not st.paused
	# Debug output so you can confirm
	print("Paused? ", st.paused)
	

func _enter_tree() -> void:
	# Main keeps running so it can listen for the key even when paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
func _set_pausable_recursive(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_PAUSABLE
	for c in n.get_children():
		_set_pausable_recursive(c)
		
func _mark_simulation_pausable() -> void:
	# if has_node("Beach"):      _set_pausable_recursive($Beach)
	# if has_node("Vendors"):    _set_pausable_recursive($Vendors)
	if has_node("Consumers"):  _set_pausable_recursive($Consumers)
	if _spawn_timer:           _spawn_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Camera can stay ALWAYS if you want to pan while paused; otherwise set PAUSABLE
	if has_node("Camera2D"):   $Camera2D.process_mode = Node.PROCESS_MODE_ALWAYS

var _pause_armed: bool = false
var _ui_armed: bool = false

# Remove any toggle code from _process/_unhandled_input and use this:
func _input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_level += zoom_step
				_apply_zoom()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_level -= zoom_step
				_apply_zoom()
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_panning = true
				_last_mouse = mb.position
		else:
			if mb.button_index == MOUSE_BUTTON_MIDDLE:
				_panning = false

	# Drag to pan
	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		cam.position -= mm.relative / zoom_level
		_clamp_camera_to_world()
		
	# UI visibility toggle (Z)
	if event.is_action_pressed(UI_TOGGLE_ACTION) and not _ui_armed:
		_ui_armed = true
		set_ui_visible(not ui_visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(UI_TOGGLE_ACTION):
		_ui_armed = false
		
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.physical_keycode == KEY_SPACE:
			var st := get_tree()
			st.paused = not st.paused
			print("Paused? ", st.paused)
			get_viewport().set_input_as_handled()  # stop UI from re-handling Space

	# 1 → [0.05, 0.95]
	if event.is_action_pressed(PRESET_WIDE_ACTION) and not _preset1_armed:
		_preset1_armed = true
		_set_vendor_positions(0.05, 0.95, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(PRESET_WIDE_ACTION):
		_preset1_armed = false

	# 2 → [0.49, 0.51]
	if event.is_action_pressed(PRESET_CENTERED_ACTION) and not _preset2_armed:
		_preset2_armed = true
		_set_vendor_positions(0.49, 0.51, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(PRESET_CENTERED_ACTION):
		_preset2_armed = false

func set_ui_font_size(v: int) -> void:
	ui_font_size = clampi(v, 8, 64)
	_apply_global_ui_font_size()
	if ui_root and ui_root.has_node("PricingBox"):
		await _dock_top_right(ui_root.get_node("PricingBox") as Control)

func _apply_global_ui_font_size() -> void:
	if ui_root == null:
		return
	# Remove local overrides so inheritance works
	_strip_local_font_overrides(ui_root)

	# Build a theme with a global default font size
	var th := Theme.new()
	# Preserve any existing styles (borders, sliders, etc.)
	if ui_root.theme != null:
		th.merge_with(ui_root.theme)

	# Set defaults
	th.default_font = ThemeDB.fallback_font
	th.default_font_size = ui_font_size

	# For reliability, also set class-specific sizes that many controls read
	for cls in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton",
		"LineEdit", "RichTextLabel", "SpinBox", "HSlider", "VSlider"]:
		th.set_font_size("font_size", cls, ui_font_size)

	ui_root.theme = th

	# Nudge layout to recalc
	ui_root.propagate_call("update_minimum_size")
	ui_root.queue_redraw()

func _strip_local_font_overrides(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			var ctrl := c as Control
			# Remove any local overrides that block the global theme
			ctrl.remove_theme_font_override("font")
			ctrl.remove_theme_font_size_override("font_size")
			_strip_local_font_overrides(ctrl)
			

# World bounds for camera settings
# The visible "world" we allow the camera to show: full beach+sea area.
func _world_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(Vector2.ZERO, vp)  # full scene: (0,0) .. (viewport size)

# Smallest allowed zoom (can't zoom out beyond world)
func _min_zoom_for_world() -> float:
	var vp := get_viewport_rect().size
	var w := _world_rect()
	# Godot: visible_world_size = viewport_size / zoom
	# To avoid seeing beyond: zoom >= viewport/world
	return max(vp.x / w.size.x, vp.y / w.size.y)

func _apply_zoom() -> void:
	var zmin := _min_zoom_for_world()
	zoom_level = clampf(zoom_level, zmin, zoom_max)
	cam.zoom = Vector2(zoom_level, zoom_level)
	_clamp_camera_to_world()

func _clamp_camera_to_world() -> void:
	var w := _world_rect()
	var vp := get_viewport_rect().size
	var half := vp * 0.5 / zoom_level

	var min_x := w.position.x + half.x
	var max_x := w.position.x + w.size.x - half.x
	var min_y := w.position.y + half.y
	var max_y := w.position.y + w.size.y - half.y

	var p := cam.position
	# If world smaller than view in any axis, lock to center on that axis
	p.x = w.position.x + w.size.x * 0.5 if min_x > max_x else clampf(p.x, min_x, max_x)
	p.y = w.position.y + w.size.y * 0.5 if min_y > max_y else clampf(p.y, min_y, max_y)
	cam.position = p

func set_ui_visible(v: bool) -> void:
	ui_visible = v
	if ui_root:
		ui_root.visible = ui_visible

func _ensure_input_actions() -> void:
	# existing pause action (keep yours if already present)
	if not InputMap.has_action(PAUSE_ACTION):
		InputMap.add_action(PAUSE_ACTION)
		var evp := InputEventKey.new()
		evp.physical_keycode = KEY_SPACE
		InputMap.action_add_event(PAUSE_ACTION, evp)

	# NEW: toggle UI on Z
	if not InputMap.has_action(UI_TOGGLE_ACTION):
		InputMap.add_action(UI_TOGGLE_ACTION)
		var evu := InputEventKey.new()
		evu.physical_keycode = KEY_Z
		InputMap.action_add_event(UI_TOGGLE_ACTION, evu)
		
	if not InputMap.has_action(PRESET_WIDE_ACTION):
		InputMap.add_action(PRESET_WIDE_ACTION)
		var e1 := InputEventKey.new(); e1.physical_keycode = KEY_1
		InputMap.action_add_event(PRESET_WIDE_ACTION, e1)
		var e1k := InputEventKey.new(); e1k.physical_keycode = KEY_KP_1
		InputMap.action_add_event(PRESET_WIDE_ACTION, e1k)  # keypad 1

	if not InputMap.has_action(PRESET_CENTERED_ACTION):
		InputMap.add_action(PRESET_CENTERED_ACTION)
		var e2 := InputEventKey.new(); e2.physical_keycode = KEY_2
		InputMap.action_add_event(PRESET_CENTERED_ACTION, e2)
		var e2k := InputEventKey.new(); e2k.physical_keycode = KEY_KP_2
		InputMap.action_add_event(PRESET_CENTERED_ACTION, e2k)  # keypad 2

func _on_toggle_ui_pressed() -> void:
	ui_visible = not ui_visible
	_apply_ui_visible()
	
func _apply_ui_visible() -> void:
	if ui_root:
		ui_root.visible = ui_visible
	if has_node("UIToggle/ToggleUIButton"):
		var b := get_node("UIToggle/ToggleUIButton") as Button
		b.text = "Show UI" if not ui_visible else "Hide UI"

func _set_vendor_positions(a_norm: float, b_norm: float, reset_stats: bool = true) -> void:
	# Move Vendor A
	if vendor_a.has_method("set_x_norm"):
		vendor_a.call("set_x_norm", a_norm)
	else:
		vendor_a.set("x_norm", a_norm)

	# Move Vendor B
	if vendor_b.has_method("set_x_norm"):
		vendor_b.call("set_x_norm", b_norm)
	else:
		vendor_b.set("x_norm", b_norm)

	_update_from_vendor_positions()
	_retarget_consumers()
	if reset_stats:
		reset_sales_ui()
