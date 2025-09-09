# scripts/Consumer.gd
# A single consumer that walks horizontally toward its chosen vendor.
class_name Consumer
extends Node2D

signal arrived(world_pos: Vector2)

@export var speed: float = 60.0
@export var icon: Texture2D        # assign a beach_person*.png
@export var pixel_scale: int = 2   # 1,2,3… (2 makes 32×32 on screen)

var target_x: float = 0.0
var done: bool = false
var color: Color = Color(0.15, 0.15, 0.15, 1.0)

func _ready() -> void:
	z_index = 20
	set_process(true)
	# crisp pixels
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED

func setup(start_pos: Vector2, target_x_px: float, hue_offset: float = 0.0) -> void:
	position = start_pos
	target_x = target_x_px
	done = false
	# keep color around if you use it elsewhere
	color = Color.from_hsv(fmod(0.60 + hue_offset, 1.0), 0.2, 0.35, 1.0)
	queue_redraw()

func _process(delta: float) -> void:
	if done:
		return
	var dx: float = target_x - position.x
	var step: float = speed * delta * (0.0 if is_zero_approx(dx) else signf(dx))
	if absf(dx) <= absf(step):
		position.x = target_x
		done = true
		emit_signal("arrived", global_position)
		queue_free()
		return
	position.x += step
	queue_redraw()

func _draw() -> void:
	if icon != null:
		var w: float = float(icon.get_width())
		var h: float = float(icon.get_height())
		var size := Vector2(w * float(pixel_scale), h * float(pixel_scale))
		# center on this node
		var rect := Rect2(-size * 0.5, size)
		draw_texture_rect(icon, rect, false)
	else:
		# fallback: little dot if no icon set
		draw_circle(Vector2.ZERO, 4.0, color)
