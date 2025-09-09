extends Node2D
# class_name Vendor  # (optional)

@export var color: Color = Color.RED
@export var label: String = "A"
@export var x_norm: float = 0.25                  # normalized [0..1]
@export var size: Vector2 = Vector2(64.0, 64.0)   # visual box size
@export var label_font: Font                      # optional; leave empty to use fallback
@export var icon: Texture2D
@export var use_texture: bool = true


var dragging: bool = false
var beach: Node2D                                  # we'll fetch Beach at runtime

func _ready() -> void:
	z_index = 10
	beach = get_parent().get_parent().get_node("Beach") as Node2D
	set_x_norm(x_norm)
	set_process_input(true)
	queue_redraw()

func set_x_norm(new_x: float) -> void:
	x_norm = clampf(new_x, 0.0, 1.0)
	var target: Vector2 = (beach as Object).call("norm_to_px", x_norm) as Vector2
	position = target
	queue_redraw()

func _draw() -> void:
	var rect: Rect2 = Rect2(-size * 0.5, size)
	if use_texture and icon != null:
		# Fit the icon into your existing hitbox 'size'
		draw_texture_rect(icon, rect, false)
	else:
		draw_rect(rect, color)

	# (Optional label—comment out if you don't want letters anymore)
	# var font_to_use: Font = label_font if label_font != null else ThemeDB.fallback_font
	# if font_to_use != null:
	#     draw_string(font_to_use, Vector2(-5.0, -10.0), label,
	#         HORIZONTAL_ALIGNMENT_CENTER, 100.0, 14, Color.BLACK)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			# Use local mouse position (camera-safe)
			var local: Vector2 = get_local_mouse_position()
			var rect := Rect2(-size * 0.5, size)
			if rect.has_point(local):
				dragging = true
				# (optional) reset stats on drag start
				var main: Node = get_parent().get_parent()
				if main.has_method("reset_sales_ui"):
					main.call("reset_sales_ui")
				get_viewport().set_input_as_handled()
		else:
			dragging = false

	elif event is InputEventMouseMotion and dragging:
		# Use world mouse x (camera-safe)
		var mouse_x_world: float = get_global_mouse_position().x
		var new_norm: float = (beach as Object).call("px_to_norm", mouse_x_world) as float
		set_x_norm(new_norm)

		# notify Main to recompute
		var main: Node = get_parent().get_parent()
		if main.has_method("_update_from_vendor_positions"):
			main.call("_update_from_vendor_positions")
		if main.has_method("_retarget_consumers"):
			main.call("_retarget_consumers")
